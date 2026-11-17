import SwiftUI

/// The CPU menu's fan rows; a view item, because AppKit greys a text row that has no action.
struct FanMenuSummary: View {
    let fans: [FanReading]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(fans.enumerated()), id: \.offset) { index, fan in
                HStack {
                    Text(FanReading.name(index: index, count: fans.count))
                    Spacer()
                    Text(fan.speedText).monospacedDigit()
                }
            }
        }
        .font(Font(NSFont.menuFont(ofSize: 0)))
        .padding(.horizontal, Theme.Size.menuItemInset)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(width: Theme.Size.diskMenuSummaryWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A menu sizes a view item by its frame, so the hosting view takes its fitting size up front.
    static func menuItem(fans: [FanReading]) -> NSMenuItem {
        let host = NSHostingView(rootView: FanMenuSummary(fans: fans))
        host.frame.size = host.fittingSize
        let item = NSMenuItem()
        item.view = host
        return item
    }
}
