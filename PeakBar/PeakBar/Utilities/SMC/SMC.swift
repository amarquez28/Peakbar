//
//  SMC.swift
//  PeakBar
//
//  Minimal, self-contained reader for the Apple System Management Controller
//  (SMC) over IOKit's AppleSMC user client. Used to read thermal sensors that
//  Apple does not expose through any public high-level API.
//
//  IMPORTANT: the SMC request/response is a fixed 80-byte C struct
//  (SMCKeyData_t). Swift does NOT guarantee struct field order or size, so we
//  build the request as a raw [UInt8] buffer and read/write fields at explicit
//  byte offsets. (An equivalent Swift `struct` compiled to 76 bytes and every
//  call failed with kIOReturnBadArgument.)
//
//  Requires the App Sandbox to be DISABLED (see CLAUDE.md / README).
//

import Foundation
import IOKit

final class SMC {
    static let shared = SMC()

    // SMCKeyData_t field offsets within the 80-byte struct.
    private enum Offset {
        static let key = 0          // UInt32
        static let keyInfoSize = 28 // UInt32 (keyInfo.dataSize)
        static let keyInfoType = 32 // UInt32 (keyInfo.dataType)
        static let result = 40      // UInt8
        static let data8 = 42       // UInt8
        static let data32 = 44      // UInt32
        static let bytes = 48       // 32 bytes
        static let structSize = 80
    }

    // AppleSMC user-client selectors.
    private enum Selector {
        static let handleYPCEvent: UInt8 = 2
        static let readKey: UInt8 = 5
        static let getKeyFromIndex: UInt8 = 8
        static let getKeyInfo: UInt8 = 9
    }

    private var connection: io_connect_t = 0
    private let isOpen: Bool

    private init() {
        let device = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard device != 0 else {
            isOpen = false
            return
        }
        defer { IOObjectRelease(device) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(device, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            isOpen = false
            return
        }
        connection = conn
        isOpen = true
    }

    deinit {
        if isOpen {
            IOServiceClose(connection)
        }
    }

    // MARK: - Public API

    /// Reads a numeric SMC key (an `flt` float or `sp78` fixed-point value) and
    /// returns it as a Double, or nil if the key is absent / unreadable / not a
    /// recognized numeric type. Used for both temperatures (°C) and fan RPM.
    func value(forKey key: String) -> Double? {
        guard let value = readKey(Self.fourCharCode(key)) else { return nil }
        return Self.decodeFloat(type: value.type, bytes: value.bytes)
    }

    /// Convenience alias for temperature sensors. Same decoding as `value(forKey:)`.
    func temperature(forKey key: String) -> Double? {
        value(forKey: key)
    }

    /// Enumerates every SMC key and returns those whose name starts with the
    /// given prefix (e.g. "Tp" for CPU cores, "Tg" for GPU). Used so PeakBar can
    /// adapt to whatever sensor keys a given Apple Silicon chip exposes instead
    /// of hardcoding per-chip lists.
    func keys(matchingPrefix prefix: String) -> [String] {
        guard isOpen, let countValue = readKey(Self.fourCharCode("#KEY")), countValue.bytes.count >= 4 else {
            return []
        }
        // #KEY holds the total key count as a big-endian UInt32.
        let total = (UInt32(countValue.bytes[0]) << 24)
                  | (UInt32(countValue.bytes[1]) << 16)
                  | (UInt32(countValue.bytes[2]) << 8)
                  | UInt32(countValue.bytes[3])

        var matches: [String] = []
        for index in 0..<total {
            var input = [UInt8](repeating: 0, count: Offset.structSize)
            input[Offset.data8] = Selector.getKeyFromIndex
            Self.setU32(&input, Offset.data32, index)
            guard let output = call(input), output[Offset.result] == 0 else { continue }
            let name = Self.string(fromFourCharCode: Self.getU32(output, Offset.key))
            if name.hasPrefix(prefix) {
                matches.append(name)
            }
        }
        return matches
    }

    // MARK: - Low-level read

    private func readKey(_ key: UInt32) -> (type: String, bytes: [UInt8])? {
        guard isOpen else { return nil }

        // Step 1: look up the key's data size and type.
        var input = [UInt8](repeating: 0, count: Offset.structSize)
        Self.setU32(&input, Offset.key, key)
        input[Offset.data8] = Selector.getKeyInfo
        guard let info = call(input), info[Offset.result] == 0 else { return nil }

        let dataSize = Self.getU32(info, Offset.keyInfoSize)
        let dataType = Self.getU32(info, Offset.keyInfoType)
        guard dataSize > 0 else { return nil }

        // Step 2: read the actual bytes.
        input = [UInt8](repeating: 0, count: Offset.structSize)
        Self.setU32(&input, Offset.key, key)
        Self.setU32(&input, Offset.keyInfoSize, dataSize)
        input[Offset.data8] = Selector.readKey
        guard let value = call(input), value[Offset.result] == 0 else { return nil }

        let count = min(Int(dataSize), 32)
        let bytes = Array(value[Offset.bytes ..< (Offset.bytes + count)])
        return (Self.string(fromFourCharCode: dataType), bytes)
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var input = input
        var output = [UInt8](repeating: 0, count: Offset.structSize)
        var outputSize = Offset.structSize

        let result = input.withUnsafeMutableBytes { inPtr -> kern_return_t in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(
                    connection,
                    UInt32(Selector.handleYPCEvent),
                    inPtr.baseAddress,
                    Offset.structSize,
                    outPtr.baseAddress,
                    &outputSize
                )
            }
        }
        return result == kIOReturnSuccess ? output : nil
    }

    // MARK: - Decoding helpers

    private static func decodeFloat(type: String, bytes: [UInt8]) -> Double? {
        // Apple Silicon sensors (temps and fan RPM) are 32-bit little-endian floats ("flt").
        if type.hasPrefix("flt"), bytes.count >= 4 {
            var value: Float32 = 0
            withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: bytes[0..<4]) }
            return Double(value)
        }
        // Older fixed-point format: signed 7.8, big-endian.
        if type.hasPrefix("sp78"), bytes.count >= 2 {
            return Double((Int16(bytes[0]) << 8) | Int16(bytes[1])) / 256.0
        }
        return nil
    }

    private static func setU32(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        buffer[offset] = UInt8(value & 0xFF)
        buffer[offset + 1] = UInt8((value >> 8) & 0xFF)
        buffer[offset + 2] = UInt8((value >> 16) & 0xFF)
        buffer[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private static func getU32(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(buffer[offset])
            | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16)
            | (UInt32(buffer[offset + 3]) << 24)
    }

    private static func fourCharCode(_ string: String) -> UInt32 {
        let chars = Array(string.utf8)
        guard chars.count == 4 else { return 0 }
        return (UInt32(chars[0]) << 24) | (UInt32(chars[1]) << 16)
             | (UInt32(chars[2]) << 8) | UInt32(chars[3])
    }

    private static func string(fromFourCharCode code: UInt32) -> String {
        let chars: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: chars, encoding: .ascii) ?? ""
    }
}
