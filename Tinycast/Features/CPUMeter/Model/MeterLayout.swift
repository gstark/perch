import CoreGraphics

/// Where each core's bar sits in the menu-bar image: one row, each bar filled from the bottom.
struct MeterLayout: Equatable, Sendable {
    static let barWidth: CGFloat = 6
    static let barHeight: CGFloat = 16
    static let gap: CGFloat = 2

    let coreCount: Int
    let efficiencyCount: Int

    init(coreCount: Int, efficiencyCount: Int = 0) {
        self.coreCount = max(coreCount, 0)
        self.efficiencyCount = min(max(efficiencyCount, 0), self.coreCount)
    }

    var size: CGSize {
        let bars = CGFloat(coreCount) * Self.barWidth
        let gaps = CGFloat(max(coreCount - 1, 0)) * Self.gap
        return CGSize(width: bars + gaps, height: Self.barHeight)
    }

    /// Cores in draw order: performance first, then the efficiency cluster macOS numbers lowest.
    var order: [Int] { Array(efficiencyCount..<coreCount) + Array(0..<efficiencyCount) }

    func isEfficiency(_ core: Int) -> Bool { core < efficiencyCount }

    /// The slot's whole bar, track included; y grows downward, so the fill rises from `maxY`.
    func bar(atSlot slot: Int) -> CGRect {
        let x: CGFloat = CGFloat(slot) * (Self.barWidth + Self.gap)
        return CGRect(x: x, y: 0, width: Self.barWidth, height: Self.barHeight)
    }
}
