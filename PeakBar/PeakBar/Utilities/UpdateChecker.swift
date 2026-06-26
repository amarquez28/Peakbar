//
//  UpdateChecker.swift
//  PeakBar
//
//  Lightweight "check for updates" against the GitHub Releases API. It does NOT
//  auto-install (that would need Sparkle + a Developer ID signature to be safe);
//  it just detects whether a newer release exists and points the user at the
//  download page. Fits PeakBar's "re-download the DMG" model.
//

import Foundation
import Combine

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let repo = "amarquez28/Peakbar"
    private let lastCheckKey = "lastUpdateCheck"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Checks GitHub Releases for a newer version.
    /// - Parameter silent: background daily check — don't surface "up to date"
    ///   or errors, only flip to `.updateAvailable` if there's genuinely a newer one.
    func check(silent: Bool = false) {
        if case .checking = state { return }
        if !silent { state = .checking }

        Task {
            do {
                let latest = try await fetchLatestRelease()
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
                if Self.isNewer(latest.version, than: currentVersion) {
                    state = .updateAvailable(version: latest.version, url: latest.url)
                } else if !silent {
                    state = .upToDate
                }
            } catch {
                if !silent { state = .failed("Couldn’t check for updates.") }
            }
        }
    }

    /// Runs a silent check at most once per day (called on launch).
    func checkInBackgroundIfDue() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        check(silent: true)
    }

    // MARK: - Networking

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    private func fetchLatestRelease() async throws -> (version: String, url: URL) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PeakBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        let page = URL(string: release.html_url)
            ?? URL(string: "https://github.com/\(repo)/releases")!
        return (Self.normalize(release.tag_name), page)
    }

    // MARK: - Version comparison

    /// Strips a leading "v" and surrounding whitespace ("v1.2.0" -> "1.2.0").
    static func normalize(_ tag: String) -> String {
        var version = tag.trimmingCharacters(in: .whitespaces)
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        return version
    }

    /// Component-wise numeric semantic-version comparison.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = normalize(candidate).split(separator: ".").map { Int($0) ?? 0 }
        let b = normalize(current).split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
