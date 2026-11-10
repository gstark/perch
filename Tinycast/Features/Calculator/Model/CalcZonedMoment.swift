import Foundation

/// A moment written the way a web page prints one. See docs/features/calculator.md.
enum CalcZonedMoment {
    struct Moment: Equatable, Sendable {
        let date: Date
        let zone: TimeZone
        let hasDate: Bool
    }

    private struct Parts {
        var year: Int?
        var month: Int?
        var day: Int?
        var clock: (hour: Int, minute: Int, second: Int)?
        var zone: TimeZone?
    }

    static func evaluate(_ raw: String, now: Date, calendar: Calendar) -> CalcResult? {
        guard raw.count <= 256 else { return nil }
        var words = words(raw)
        guard words.count >= 2 else { return nil }
        let target = splitTarget(&words)
        if target == .unresolved { return nil }
        guard let parts = parse(words), parts.clock != nil, parts.zone != nil || target != .none
        else { return nil }
        guard let moment = moment(parts, now: now, calendar: calendar) else { return nil }
        let zone: TimeZone
        if case .zone(let named) = target { zone = named } else { zone = calendar.timeZone }
        return result(moment, target: zone, now: now, calendar: calendar)
    }

    /// The first written moment in free text, read line by line, for pasted pages and OCR.
    static func find(in text: String, now: Date, calendar: Calendar) -> Moment? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.allSatisfy(\.isWhitespace)
        }
        guard !lines.isEmpty, lines.count <= 400 else { return nil }
        // Pages split a date and its clock over lines, so neighbours join before a line stands alone.
        for width in [3, 2, 1] {
            for start in lines.indices where start + width <= lines.count {
                let words = words(lines[start..<(start + width)].joined(separator: " "))
                guard words.count <= 16, let parts = parse(words), parts.clock != nil, parts.zone != nil
                else { continue }
                if let moment = moment(parts, now: now, calendar: calendar) { return moment }
            }
        }
        return nil
    }

    /// What the palette opens on for copied text: the text itself when it reads, else what it holds.
    static func seed(from text: String, now: Date, calendar: Calendar) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(where: \.isNewline), evaluate(trimmed, now: now, calendar: calendar) != nil {
            return trimmed
        }
        return find(in: text, now: now, calendar: calendar).map { query(for: $0, calendar: calendar) }
    }

    /// A query this grammar reads back to `moment`, spelled the same whatever the locale.
    static func query(for moment: Moment, calendar: Calendar) -> String {
        var source = calendar
        source.timeZone = moment.zone
        let parts = source.dateComponents([.year, .month, .day, .hour, .minute, .second], from: moment.date)
        var clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if let second = parts.second, second != 0 { clock += String(format: ":%02d", second) }
        let date = String(format: "%04d-%02d-%02d ", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return (moment.hasDate ? date : "") + clock + " " + zoneWord(moment.zone, at: moment.date)
    }

    /// The city when it reads back to this very zone, else the offset in force at that moment.
    private static func zoneWord(_ zone: TimeZone, at date: Date) -> String {
        let city = CalcTimeZone.label(for: zone).lowercased()
        let words = city.split(separator: " ").map(String.init)
        if CalcTimeZone.zone(named: words)?.identifier == zone.identifier { return city }
        return CalcTimeZone.label(for: TimeZone(secondsFromGMT: zone.secondsFromGMT(for: date)) ?? zone)
            .lowercased()
    }

    /// The moment a typed query names, read in the Mac's zone when it names none: `3pm`, `9am tokyo`.
    static func reference(_ query: String, now: Date, calendar: Calendar) -> Moment? {
        let words = words(query)
        guard !words.isEmpty, words.count <= 16, let parts = parse(words), parts.clock != nil else {
            return nil
        }
        return moment(parts, now: now, calendar: calendar)
    }

    static func result(_ moment: Moment, target: TimeZone, now: Date, calendar: Calendar) -> CalcResult? {
        let display: String
        let expression: String
        if moment.hasDate {
            var here = calendar
            here.timeZone = moment.zone
            let sameYear = here.component(.year, from: moment.date) == here.component(.year, from: now)
            let template = sameYear ? "EEEMMMdjmm" : "EEEMMMdyjmm"
            expression = CalcDateFormatters.string(
                from: moment.date, calendar: calendar, zone: moment.zone, template: template)
            display = CalcDateFormatters.string(
                from: moment.date, calendar: calendar, zone: target, template: template)
        } else {
            guard let note = CalcTimeZone.dayOffsetNote(
                moment.date, from: moment.zone, to: target, calendar: calendar)
            else { return nil }
            expression = CalcDateFormatters.string(
                from: moment.date, calendar: calendar, zone: moment.zone, template: "jmm")
            let time = CalcDateFormatters.string(
                from: moment.date, calendar: calendar, zone: target, template: "jmm")
            return CalcResult(
                expression: expression,
                sourceBadge: CalcTimeZone.label(for: moment.zone),
                targetBadge: CalcTimeZone.label(for: target),
                payload: .value(display: time + note, copyText: time))
        }
        return CalcResult(
            expression: expression,
            sourceBadge: CalcTimeZone.label(for: moment.zone),
            targetBadge: CalcTimeZone.label(for: target),
            payload: .value(display: display, copyText: display))
    }

    // MARK: - Words

    private static func words(_ raw: String) -> [String] {
        var text = raw.lowercased()
            .replacingOccurrences(of: "a.m.", with: "am")
            .replacingOccurrences(of: "p.m.", with: "pm")
            .replacingOccurrences(of: "\u{2212}", with: "-")
        for mark in ["(", ")", "[", "]", ",", "|", ";", "\u{00B7}", "\u{2022}"] {
            text = text.replacingOccurrences(of: mark, with: " ")
        }
        return text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private enum Target: Equatable {
        case none
        case unresolved
        case zone(TimeZone)
    }

    private static func splitTarget(_ words: inout [String]) -> Target {
        guard let connector = words.lastIndex(where: { ["in", "to", "->", "\u{2192}"].contains($0) })
        else { return .none }
        let tail = Array(words[(connector + 1)...])
        guard let zone = wholeZone(tail) else { return .unresolved }
        words = Array(words[..<connector])
        return .zone(zone)
    }

    private static func wholeZone(_ words: [String]) -> TimeZone? {
        guard !words.isEmpty, let (zone, used) = zone(at: 0, in: words), used == words.count
        else { return nil }
        return zone
    }

    // MARK: - Grammar

    /// Every word must be claimed, so an unrelated sentence never earns a card.
    private static func parse(_ words: [String]) -> Parts? {
        var parts = Parts()
        var index = 0
        while index < words.count {
            let word = words[index]
            let bare = word.hasSuffix(".") ? String(word.dropLast()) : word
            if fillers.contains(bare) || weekdays.contains(bare) {
                index += 1
            } else if bare == "at", parts.month != nil, parts.clock == nil {
                // `Nov 10 at 7:36`; anywhere else `at` is the zone grammar's connector.
                index += 1
            } else if let month = months[bare] {
                guard parts.month == nil else { return nil }
                parts.month = month
                index += 1
            } else if let date = numericDate(word) {
                guard parts.year == nil, parts.month == nil, parts.day == nil else { return nil }
                (parts.year, parts.month, parts.day) = date
                index += 1
            } else if let clock = clock(word, meridiem: words[safe: index + 1]) {
                guard parts.clock == nil else { return nil }
                parts.clock = clock.value
                index += clock.used
            } else if let number = dayOrYear(word) {
                if number >= 1000 {
                    guard parts.year == nil else { return nil }
                    parts.year = number
                } else {
                    guard parts.day == nil else { return nil }
                    parts.day = number
                }
                index += 1
            } else if let (zone, used) = zone(at: index, in: words) {
                guard parts.zone == nil else { return nil }
                parts.zone = zone
                index += used
            } else {
                return nil
            }
        }
        // A day number means nothing without its month, and a month nothing without its day.
        guard (parts.day == nil) == (parts.month == nil), parts.year == nil || parts.month != nil
        else { return nil }
        return parts
    }

    private static func moment(_ parts: Parts, now: Date, calendar: Calendar) -> Moment? {
        guard let clock = parts.clock else { return nil }
        let zone = parts.zone ?? calendar.timeZone
        var source = calendar
        source.timeZone = zone
        let today = source.dateComponents([.year, .month, .day], from: now)
        var components = DateComponents()
        components.year = parts.year ?? today.year
        components.month = parts.month ?? today.month
        components.day = parts.day ?? today.day
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = clock.second
        guard let date = source.date(from: components) else { return nil }
        let resolved = source.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard resolved.year == components.year, resolved.month == components.month,
            resolved.day == components.day, resolved.hour == components.hour,
            resolved.minute == components.minute
        else { return nil }
        return Moment(date: date, zone: zone, hasDate: parts.month != nil)
    }

    /// `7:36`, `07:36:00`, `7:36am`, `7:36 am`, `7am`.
    private static func clock(
        _ word: String, meridiem next: String?
    ) -> (value: (hour: Int, minute: Int, second: Int), used: Int)? {
        var text = word
        var meridiem: String?
        var used = 1
        for suffix in ["am", "pm"] where text.hasSuffix(suffix) {
            meridiem = suffix
            text.removeLast(2)
        }
        if meridiem == nil, next == "am" || next == "pm" {
            meridiem = next
            used = 2
        }
        let fields = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.count <= 2 }),
            let hour = Int(fields[0])
        else { return nil }
        let numbers = fields.dropFirst().compactMap { Int($0) }
        guard numbers.count == fields.count - 1, numbers.allSatisfy({ (0...59).contains($0) }) else {
            return nil
        }
        // A bare number is a day or a count, so only a colon or a meridiem makes a clock.
        guard fields.count > 1 || meridiem != nil else { return nil }
        let minute = numbers.first ?? 0
        let second = numbers.count > 1 ? numbers[1] : 0
        guard let meridiem else {
            guard (0...23).contains(hour) else { return nil }
            return ((hour, minute, second), used)
        }
        guard (1...12).contains(hour) else { return nil }
        return ((meridiem == "pm" ? hour % 12 + 12 : hour % 12, minute, second), used)
    }

    /// `2026-11-10`, `2026/11/10`, `10.11.2026`, and a slash date only when no reading is in doubt.
    private static func numericDate(_ word: String) -> (Int, Int, Int)? {
        for separator: Character in ["-", "/", "."] {
            let fields = word.split(separator: separator, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let numbers = fields.compactMap { Int($0) }
            guard numbers.count == 3 else { return nil }
            if fields[0].count == 4 { return validDate(numbers[0], numbers[1], numbers[2]) }
            guard fields[2].count == 4 else { return nil }
            switch separator {
            case ".": return validDate(numbers[2], numbers[1], numbers[0])
            case "/" where numbers[0] > 12: return validDate(numbers[2], numbers[1], numbers[0])
            case "/" where numbers[1] > 12: return validDate(numbers[2], numbers[0], numbers[1])
            default: return nil
            }
        }
        return nil
    }

    private static func validDate(_ year: Int, _ month: Int, _ day: Int) -> (Int, Int, Int)? {
        guard (1000...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        return (year, month, day)
    }

    /// `10`, `10th`, `2026`.
    private static func dayOrYear(_ word: String) -> Int? {
        var digits = word
        for suffix in ["st", "nd", "rd", "th"] where digits.hasSuffix(suffix) { digits.removeLast(2) }
        guard let number = Int(digits), digits.allSatisfy(\.isASCII) else { return nil }
        if digits.count == 4, (1000...9999).contains(number), digits == word { return number }
        return (1...31).contains(number) && digits.count <= 2 ? number : nil
    }

    // MARK: - Zones

    /// A zone starting at `index`: an offset, `utc+8`, or the longest place name that resolves.
    private static func zone(at index: Int, in words: [String]) -> (TimeZone, Int)? {
        let word = words[index]
        if let seconds = offset(word, allowsHoursAlone: false) { return fixed(seconds).map { ($0, 1) } }
        for prefix in ["utc", "gmt"] where word.hasPrefix(prefix) {
            let rest = String(word.dropFirst(prefix.count))
            if rest.isEmpty {
                if let next = words[safe: index + 1], let seconds = offset(next) {
                    return fixed(seconds).map { ($0, 2) }
                }
                return fixed(0).map { ($0, 1) }
            }
            return offset(rest).flatMap(fixed).map { ($0, 1) }
        }
        if word == "z" { return fixed(0).map { ($0, 1) } }
        for length in stride(from: min(4, words.count - index), through: 1, by: -1) {
            let phrase = Array(words[index..<(index + length)])
            if let zone = CalcTimeZone.zone(named: phrase) { return (zone, length) }
        }
        return nil
    }

    /// `+0800`, `+08:00`, `-5`; hours alone only after `utc`, where nothing else fits.
    private static func offset(_ text: String, allowsHoursAlone: Bool = true) -> Int? {
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let body = text.dropFirst()
        let hours: Int
        let minutes: Int
        if body.contains(":") {
            let fields = body.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 2, (1...2).contains(fields[0].count), fields[1].count == 2,
                let h = Int(fields[0]), let m = Int(fields[1])
            else { return nil }
            (hours, minutes) = (h, m)
        } else if body.count == 4, let packed = Int(body) {
            (hours, minutes) = (packed / 100, packed % 100)
        } else if (1...2).contains(body.count), let h = Int(body), allowsHoursAlone {
            (hours, minutes) = (h, 0)
        } else {
            return nil
        }
        guard body.allSatisfy(\.isASCII), hours <= 14, minutes <= 59 else { return nil }
        return (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
    }

    private static func fixed(_ seconds: Int) -> TimeZone? {
        seconds == 0 ? TimeZone(identifier: "UTC") : TimeZone(secondsFromGMT: seconds)
    }

    // MARK: - Tables

    private static let fillers: Set<String> = [
"on", "the", "of", "hrs", "approx", "around", "-", "@"
    ]

    private static let weekdays: Set<String> = [
        "sunday", "sun", "monday", "mon", "tuesday", "tue", "tues", "wednesday", "wed", "thursday",
        "thu", "thurs", "friday", "fri", "saturday", "sat"
    ]

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4,
        "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12
    ]
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
