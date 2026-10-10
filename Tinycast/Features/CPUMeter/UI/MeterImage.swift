import AppKit

/// Draws one bar per core, rising from the bottom and coloured by how busy that core is.
enum MeterImage {
    /// Efficiency cores draw muted, so the dim group reads as the small cores, not a lighter load.
    static let efficiencyAlpha: CGFloat = 0.6

    static func color(for zone: LoadZone) -> NSColor {
        switch zone {
        case .low: .systemBlue
        case .high: .systemOrange
        case .saturated: .systemRed
        }
    }

    static func make(loads: [CoreLoad], efficiencyCount: Int) -> NSImage {
        let layout = MeterLayout(coreCount: loads.count, efficiencyCount: efficiencyCount)
        let image = NSImage(size: layout.size, flipped: true) { _ in
            for (slot, core) in layout.order.enumerated() {
                let bar = layout.bar(atSlot: slot)
                let load = loads[core]
                // A faint track, so an idle core still shows where it sits.
                NSColor.labelColor.withAlphaComponent(0.15).setFill()
                bar.fill()
                let height = bar.height * min(max(load.total, 0), 1)
                let alpha = layout.isEfficiency(core) ? efficiencyAlpha : 1
                color(for: load.zone).withAlphaComponent(alpha).setFill()
                NSRect(x: bar.minX, y: bar.maxY - height, width: bar.width, height: height).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
