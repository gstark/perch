import AppKit

/// Draws one cell per core, filled left to right: user time, then system time.
enum MeterImage {
    static let userColor = NSColor(srgbRed: 0.94, green: 0.27, blue: 0.13, alpha: 1)
    static let systemColor = NSColor(srgbRed: 0.97, green: 0.95, blue: 0.20, alpha: 1)

    static func make(loads: [CoreLoad]) -> NSImage {
        let layout = MeterLayout(coreCount: loads.count)
        let image = NSImage(size: layout.size, flipped: true) { _ in
            for (core, load) in loads.enumerated() {
                let cell = layout.cell(for: core)
                // A faint track, so an idle core still shows where it sits.
                NSColor.labelColor.withAlphaComponent(0.15).setFill()
                cell.fill()
                let userWidth = cell.width * min(max(load.user, 0), 1)
                let systemWidth = min(cell.width * max(load.system, 0), cell.width - userWidth)
                userColor.setFill()
                NSRect(x: cell.minX, y: cell.minY, width: userWidth, height: cell.height).fill()
                systemColor.setFill()
                NSRect(x: cell.minX + userWidth, y: cell.minY, width: systemWidth, height: cell.height)
                    .fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
