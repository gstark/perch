import Charts
import SwiftUI

/// The CPU menu's disk row: free space now, the week's change, and a month of free space.
struct DiskMenuSummary: View {
    let current: DiskSample
    let samples: [DiskSample]
    let now: Date

    var body: some View {
        let points = DiskHistory.points(samples, over: .month, now: now)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("\(DiskBytes.text(current.available)) free of \(DiskBytes.text(current.total))")
                Spacer()
                if let change = DiskHistory.usedChange(samples, over: .week, now: now) {
                    Text("\(DiskBytes.change(change)) this week").foregroundStyle(.secondary)
                }
            }
            if points.count > 1 {
                Chart(points, id: \.date) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Free", Double(point.available)))
                        .foregroundStyle(.blue)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: Theme.Size.diskMenuSparkline)
                .accessibilityHidden(true)
            }
        }
        .font(Font(NSFont.menuFont(ofSize: 0)))
        .padding(.horizontal, Theme.Size.menuItemInset)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(width: Theme.Size.diskMenuSummaryWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A menu sizes a view item by its frame, so the hosting view takes its fitting size up front.
    static func menuItem(current: DiskSample, samples: [DiskSample]) -> NSMenuItem {
        let host = NSHostingView(rootView: DiskMenuSummary(current: current, samples: samples, now: .now))
        host.frame.size = host.fittingSize
        let item = NSMenuItem()
        item.view = host
        return item
    }
}
