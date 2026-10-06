import CoreGraphics

/// Where each core's cell sits in the menu-bar image: two rows, filled column by column.
struct MeterLayout: Equatable, Sendable {
    static let rows = 2
    static let cellWidth: CGFloat = 8
    static let cellHeight: CGFloat = 7
    static let rowGap: CGFloat = 1
    static let columnGap: CGFloat = 9

    let coreCount: Int

    var columns: Int { (coreCount + Self.rows - 1) / Self.rows }

    var size: CGSize {
        let cells = CGFloat(columns) * Self.cellWidth
        let gaps = CGFloat(max(columns - 1, 0)) * Self.columnGap
        let rowCells = CGFloat(Self.rows) * Self.cellHeight
        let rowGaps = CGFloat(Self.rows - 1) * Self.rowGap
        let width: CGFloat = cells + gaps
        let height: CGFloat = rowCells + rowGaps
        return CGSize(width: width, height: height)
    }

    /// Core 0 is the top of the first column, core 1 the bottom; y grows downward.
    func cell(for core: Int) -> CGRect {
        let column = CGFloat(core / Self.rows)
        let row = CGFloat(core % Self.rows)
        let x: CGFloat = column * (Self.cellWidth + Self.columnGap)
        let y: CGFloat = row * (Self.cellHeight + Self.rowGap)
        return CGRect(x: x, y: y, width: Self.cellWidth, height: Self.cellHeight)
    }
}
