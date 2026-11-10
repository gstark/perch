import SwiftUI

/// The clocks, redrawn on each minute so a board showing now never goes stale.
struct WorldClockList: View {
    @Environment(\.metrics) private var metrics
    let query: String
    let zones: [String]
    let moment: CalcZonedMoment.Moment?
    let calendar: Calendar
    let selectedID: String?
    /// Changes only when the list should scroll, so mouse selection never yanks the position.
    let scroll: ScrollIntent
    let onSelect: (String) -> Void
    let onActivate: () -> Void
    let onActions: (String) -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            let rows = WorldClockContent.rows(
                query: query, zones: zones, moment: moment, now: context.date, calendar: calendar)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        SectionHeader(title: WorldClockContent.title(moment, calendar: calendar), isFirst: true)
                        ForEach(rows) { row in
                            item(row)
                                .selectionFrame(row.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(row.id) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(row.id)
                                        onActivate()
                                    }
                                )
                                .onRightClick { onActions(row.id) }
                        }
                        if zones.isEmpty, moment == nil {
                            Text("Type a city, country or airport code to add a clock.")
                                .font(metrics.typography.rowTrailing)
                                .foregroundStyle(.secondary)
                                .padding(.top, metrics.spacing.lg)
                        }
                    }
                    .padding(.horizontal, metrics.spacing.md)
                    .padding(.top, metrics.spacing.xs)
                    .padding(.bottom, metrics.spacing.md)
                    .hideNativeScrollers()
                    .scrollOriginAnchor()
                }
                .edgeDissolve()
                .thinScrollbar()
                .scrollFollowsSelection(
                    scroll, row: selectedID, atOrigin: selectedID == rows.first?.id, proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func item(_ row: WorldClockScreen.Row) -> some View {
        switch row {
        case .add(let zone):
            WorldClockRowView(
                symbol: "plus.circle", title: "Add \(CalcTimeZone.label(for: zone))",
                subtitle: zone.identifier.replacingOccurrences(of: "_", with: " "), trailing: nil,
                selected: row.id == selectedID)
        case .clock(let clock):
            WorldClockRowView(
                symbol: clock.isHome ? "house" : "globe", title: clock.city,
                subtitle: "\(clock.day) · \(clock.isHome ? "This Mac" : clock.difference)",
                trailing: clock.time, selected: row.id == selectedID)
        }
    }
}

private struct WorldClockRowView: View {
    @Environment(\.metrics) private var metrics
    let symbol: String
    let title: String
    let subtitle: String
    let trailing: String?
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: symbol)).resizable()
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.xl)
            if let trailing {
                Text(trailing)
                    .font(metrics.typography.rowTitle.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
