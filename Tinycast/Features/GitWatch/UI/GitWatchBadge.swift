import AppKit

/// Git Watch's mark in the CPU item: a symbol and the at-risk count, drawn left of the meter.
enum GitWatchBadge {
    private static let height: CGFloat = 16
    private static let gap: CGFloat = 3
    private static let pointSize: CGFloat = 12

    /// Nil when no scan runs and nothing is at risk, so the item is the meter alone.
    static func make(count: Int, isScanning: Bool) -> NSImage? {
        guard count > 0 || isScanning else { return nil }
        let name = isScanning ? "arrow.triangle.2.circlepath" : "arrow.triangle.branch"
        let text = count > 0 ? "\(count)" : ""
        guard let symbolSize = symbol(name)?.size else { return nil }
        let textSize = (text as NSString).size(withAttributes: attributes())
        let width = symbolSize.width + (text.isEmpty ? 0 : gap + textSize.width)
        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            guard let symbol = symbol(name) else { return false }
            let symbolY = (height - symbolSize.height) / 2
            tinted(symbol).draw(in: NSRect(origin: NSPoint(x: 0, y: symbolY), size: symbolSize))
            let textOrigin = NSPoint(x: symbolSize.width + gap, y: (height - textSize.height) / 2)
            (text as NSString).draw(at: textOrigin, withAttributes: attributes())
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
    }

    private static func attributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
    }

    /// A symbol is a template and draws black inside an image, so the label colour goes over it.
    private static func tinted(_ symbol: NSImage) -> NSImage {
        NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
