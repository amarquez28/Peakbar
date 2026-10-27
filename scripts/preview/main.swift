import AppKit

// Renders each menu bar style onto a mock menu bar strip so the layout can be
// eyeballed at real size (and at 3x for detail). Compiled against the real
// MenuBarRenderer / MenuBarFormatter sources.

let barHeight: CGFloat = 24
let renderer = MenuBarRenderer(barHeight: barHeight)

var snap = StatsSnapshot()
snap.cpuUsage = 7
snap.gpuUsage = 43
snap.ramUsage = 21.4
snap.cpuTemp = 52
snap.gpuTemp = 38
snap.fanSpeed = 0
snap.powerWatts = 32.7
snap.batteryWatts = -12.4
snap.batteryMinutes = 134
snap.batteryTemp = 29

let allStats = StatType.allCases

struct Row {
    let label: String
    let stats: [StatType]
    let style: MenuBarStyle
}

let rows: [Row] = [
    Row(label: "labels  2", stats: [.cpu, .gpu], style: .labels),
    Row(label: "icons   2", stats: [.cpu, .gpu], style: .icons),
    Row(label: "labels 10", stats: allStats, style: .labels),
    Row(label: "icons  10", stats: allStats, style: .icons),
]

let labelFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
let labelWidth: CGFloat = 62
let scale: CGFloat = 3
let rowSpacing: CGFloat = 6

var contentWidth: CGFloat = 0
for row in rows {
    contentWidth = max(contentWidth, renderer.width(stats: row.stats, style: row.style))
}
let totalWidth = labelWidth + contentWidth + 60
let totalHeight = CGFloat(rows.count) * (barHeight + rowSpacing) + rowSpacing

let image = NSImage(size: NSSize(width: totalWidth * scale, height: totalHeight * scale))
image.lockFocus()
NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
NSGraphicsContext.current?.imageInterpolation = .none

NSColor.white.setFill()
NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight).fill()

var y = totalHeight - barHeight - rowSpacing
for row in rows {
    // Mock menu bar strip.
    NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
    NSRect(x: labelWidth, y: y, width: totalWidth - labelWidth, height: barHeight).fill()

    NSAttributedString(
        string: row.label,
        attributes: [.font: labelFont, .foregroundColor: NSColor.darkGray]
    ).draw(at: NSPoint(x: 4, y: y + 7))

    let width = renderer.width(stats: row.stats, style: row.style)
    // Item bounds, so the fixed length is visible.
    NSColor(calibratedRed: 0.2, green: 0.5, blue: 1, alpha: 0.15).setFill()
    NSRect(x: labelWidth + 6, y: y, width: width + 12, height: barHeight).fill()

    let title = renderer.attributedTitle(stats: row.stats, snapshot: snap, style: row.style)
    let mutable = NSMutableAttributedString(attributedString: title)
    mutable.addAttribute(
        .foregroundColor, value: NSColor.black,
        range: NSRange(location: 0, length: mutable.length)
    )
    mutable.draw(at: NSPoint(x: labelWidth + 12, y: y + (barHeight - title.size().height) / 2))

    print("\(row.label): \(Int(width))pt")
    y -= barHeight + rowSpacing
}
image.unlockFocus()

let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
