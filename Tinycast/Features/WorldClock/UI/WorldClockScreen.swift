import SwiftUI

/// The Mac's clock and every saved one; a typed time moves them all, a typed place adds one.
struct WorldClockScreen: PaletteScreen {
    let settings: AppSettings
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    enum Row: Equatable, Identifiable {
        case add(TimeZone)
        case clock(WorldClockRow)

        var id: String {
            switch self {
            case .add(let zone): return "add-" + zone.identifier
            case .clock(let row): return row.id
            }
        }
    }

    private var coordinator: WorldClockCoordinator { core.worldClockCoordinator }

    /// A query that names a moment shows every clock at it; any other query filters them.
    private var moment: CalcZonedMoment.Moment? {
        CalcZonedMoment.reference(vm.query, now: Date(), calendar: coordinator.calendar)
    }

    var rows: [Row] {
        WorldClockContent.rows(
            query: vm.query, zones: settings.worldClockZones, moment: moment, now: Date(),
            calendar: coordinator.calendar)
    }

    var primaryActionTitle: String {
        if case .add = row(at: vm.selection) { return "Add Clock" }
        return "Copy Time"
    }

    private func row(at selection: Int) -> Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func saved(at selection: Int) -> WorldClockRow? {
        guard case .clock(let row) = row(at: selection), !row.isHome else { return nil }
        return row
    }

    func hasActions(at selection: Int) -> Bool {
        if case .clock = row(at: selection) { return true }
        return false
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard case .clock(let row) = row(at: selection) else { return nil }
        var items = [
            PopoverMenuItem(title: "Copy Time", systemImage: "doc.on.doc", shortcut: "↵") {
                coordinator.copy(row)
            }
        ]
        if !row.isHome {
            items.append(
                PopoverMenuItem(
                    title: "Remove Clock", systemImage: "trash", startsSection: true, shortcut: "⌃X",
                    isDestructive: true
                ) {
                    coordinator.removeZone(row.zone)
                })
        }
        return PopoverMenuContent(header: "\(row.city) · \(row.day)", items: items)
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        case .add(let zone): coordinator.addZone(zone)
        case .clock(let row): coordinator.copy(row)
        case nil: break
        }
    }

    func secondary(at selection: Int) -> Bool { false }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete, .delete:
            guard let row = saved(at: selection) else { return false }
            coordinator.removeZone(row.zone)
            return true
        default: return false
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            WorldClockList(
                query: vm.query, zones: settings.worldClockZones, moment: moment,
                calendar: coordinator.calendar, selectedID: row(at: selection)?.id, scroll: scroll,
                onSelect: { id in
                    if let index = rows.firstIndex(where: { $0.id == id }) { vm.selection = index }
                },
                onActivate: { activate(at: vm.selection) },
                onActions: { id in
                    if let index = rows.firstIndex(where: { $0.id == id }) { vm.selection = index }
                    openActions()
                }))
    }
}

/// One builder for the screen's selection and the list's drawing, so the two cannot disagree.
@MainActor
enum WorldClockContent {
    static func rows(
        query: String, zones: [String], moment: CalcZonedMoment.Moment?, now: Date, calendar: Calendar
    ) -> [WorldClockScreen.Row] {
        let clocks = WorldClockBoard.rows(zones: zones, at: moment?.date ?? now, calendar: calendar)
        guard moment == nil else { return clocks.map(WorldClockScreen.Row.clock) }
        let add = WorldClockBoard.addable(query, zones: zones, home: calendar.timeZone)
        return (add.map { [.add($0)] } ?? [])
            + WorldClockBoard.matching(clocks, query: query).map(WorldClockScreen.Row.clock)
    }

    /// The header says which moment the clocks show, so a typed time can't be mistaken for now.
    static func title(_ moment: CalcZonedMoment.Moment?, calendar: Calendar) -> String {
        guard let moment else { return "Now" }
        let when = CalcDateFormatters.string(
            from: moment.date, calendar: calendar, zone: moment.zone, template: "EEEMMMdjmm")
        return "At \(when) \(CalcTimeZone.label(for: moment.zone))"
    }
}
