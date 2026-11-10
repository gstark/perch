import Foundation

/// One clock on the World Clock screen, worked out for a single moment.
struct WorldClockRow: Equatable, Identifiable, Sendable {
    /// The IANA identifier, which is also what Settings stores.
    let zone: String
    let city: String
    let time: String
    let day: String
    /// `Same time`, `+14h` or `-5h 30m`, measured from the Mac's own zone.
    let difference: String
    let isHome: Bool

    var id: String { zone }

    /// What ↵ copies: the clock with enough context to paste into a message.
    var copyText: String { "\(time) \(city) (\(day))" }
}

/// The Mac's zone first, then every saved zone, at one moment. See docs/features/world-clock.md.
enum WorldClockBoard {
    static func rows(zones: [String], at date: Date, calendar: Calendar) -> [WorldClockRow] {
        let home = calendar.timeZone
        let saved = normalized(zones).filter { $0 != home.identifier }.compactMap(TimeZone.init(identifier:))
        return ([home] + saved).map { zone in
            WorldClockRow(
                zone: zone.identifier,
                city: CalcTimeZone.label(for: zone),
                time: CalcDateFormatters.string(from: date, calendar: calendar, zone: zone, template: "jmm"),
                day: CalcDateFormatters.string(from: date, calendar: calendar, zone: zone, template: "EEEMMMd"),
                difference: zone.secondsFromGMT(for: date) == home.secondsFromGMT(for: date)
                    ? "Same time" : CalcTimeZone.differenceText(from: home, to: zone, at: date),
                isHome: zone.identifier == home.identifier)
        }
    }

    /// Unknown identifiers and repeats drop out, so a hand-edited settings.json cannot break the list.
    static func normalized(_ zones: [String]) -> [String] {
        var seen: Set<String> = []
        return zones.filter { TimeZone(identifier: $0) != nil && seen.insert($0).inserted }
    }

    /// The saved clocks a filter keeps; the home row always stays, as the reference for the rest.
    static func matching(_ rows: [WorldClockRow], query: String) -> [WorldClockRow] {
        let needle = fold(query)
        guard !needle.isEmpty else { return rows }
        return rows.filter { $0.isHome || fold($0.city).contains(needle) || fold($0.zone).contains(needle) }
    }

    /// A place the query names that is not on the board yet, offered as an Add row.
    static func addable(_ query: String, zones: [String], home: TimeZone) -> TimeZone? {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, let zone = CalcTimeZone.zone(named: words),
            zone.identifier != home.identifier, !zones.contains(zone.identifier)
        else { return nil }
        return zone
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "_", with: " ")
    }
}
