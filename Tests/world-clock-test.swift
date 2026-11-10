import Foundation

/// The World Clock board, and the timestamp reading the clipboard command and the screen share.
@main
@MainActor
struct WorldClockTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ expected: String, _ got: String?) {
        if got == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(label)\n      expected: \(expected)\n      got:      \(got ?? "nil")")
        }
    }

    /// Tue 2026-11-10 15:00 UTC; Chicago is on CST, so it reads 09:00.
    static let now = Date(timeIntervalSince1970: 1_794_322_800)

    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    static func main() {
        board()
        seeds()
        references()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func board() {
        let chicago = calendar("America/Chicago")
        let rows = WorldClockBoard.rows(
            zones: ["Asia/Tokyo", "Bogus/Zone", "Asia/Tokyo", "America/Chicago", "Asia/Kolkata"],
            at: now, calendar: chicago)
        check("home leads, repeats and unknown zones drop", "Chicago Tokyo Kolkata",
            rows.map(\.city).joined(separator: " "))
        check("home time", "9:00 AM", rows[0].time)
        check("home difference", "Same time", rows[0].difference)
        check("tokyo time", "12:00 AM", rows[1].time)
        check("tokyo day", "Wed, Nov 11", rows[1].day)
        check("tokyo difference", "+15h", rows[1].difference)
        check("half-hour difference", "+11h 30m", rows[2].difference)
        check("copy text", "12:00 AM Tokyo (Wed, Nov 11)", rows[1].copyText)
        check("filter keeps home", "Chicago Tokyo",
            WorldClockBoard.matching(rows, query: "tok").map(\.city).joined(separator: " "))
        check("filter folds", "Chicago Kolkata",
            WorldClockBoard.matching(rows, query: "KOLK").map(\.city).joined(separator: " "))
        let home = chicago.timeZone
        check("addable place", "Europe/Paris",
            WorldClockBoard.addable("paris", zones: ["Asia/Tokyo"], home: home)?.identifier)
        check("saved place is not addable", "nil",
            WorldClockBoard.addable("tokyo", zones: ["Asia/Tokyo"], home: home)?.identifier ?? "nil")
        check("home is not addable", "nil",
            WorldClockBoard.addable("dallas", zones: [], home: home)?.identifier ?? "nil")
    }

    static func seeds() {
        let chicago = calendar("America/Chicago")
        let page = "Shipment picked up\nNovember 10, 2026\n7:36 AM (UTC +08:00)\nSingapore - Hub"
        check("page seeds a canonical query", "2026-11-10 07:36 utc+8",
            CalcZonedMoment.seed(from: page, now: now, calendar: chicago))
        check("a readable line seeds itself", "nov 10 7:36am in tokyo",
            CalcZonedMoment.seed(from: "  nov 10 7:36am in tokyo\n", now: now, calendar: chicago))
        check("a named zone keeps its city", "2026-11-10 07:36 singapore",
            CalcZonedMoment.seed(from: "Tue 10 Nov 2026\n07:36 SGT", now: now, calendar: chicago))
        check("an alias city keeps its city", "2026-11-10 07:36 kolkata",
            CalcZonedMoment.seed(from: "Nov 10, 2026\n7:36 AM IST", now: now, calendar: chicago))
        // `indianapolis` is curated to New York, so reading it back would name another zone.
        let indiana = CalcZonedMoment.Moment(
            date: now, zone: TimeZone(identifier: "America/Indiana/Indianapolis")!, hasDate: true)
        check("a city that reads back elsewhere uses the offset", "2026-11-10 10:00 utc-5",
            CalcZonedMoment.query(for: indiana, calendar: chicago))
        check("text without a moment", "nil",
            CalcZonedMoment.seed(from: "Hello\nworld", now: now, calendar: chicago) ?? "nil")
        for seed in ["2026-11-10 07:36 utc+8", "2026-11-10 07:36 singapore", "2026-11-10 07:36 utc+5:30"] {
            check("seed reads back: \(seed)", "true",
                String(CalcEngine.evaluate(seed, now: now, calendar: chicago) != nil))
        }
    }

    static func references() {
        let chicago = calendar("America/Chicago")
        let utc = calendar("UTC")
        func at(_ query: String) -> String? {
            CalcZonedMoment.reference(query, now: now, calendar: chicago).map {
                CalcDateFormatters.string(from: $0.date, calendar: utc, zone: utc.timeZone, pattern: "yyyy-MM-dd HH:mm")
            }
        }
        check("bare clock is the Mac's zone", "2026-11-10 21:00", at("3pm"))
        check("clock in a named zone is today there", "2026-11-11 00:00", at("9am tokyo"))
        check("date and offset", "2026-11-09 23:36", at("nov 10 7:36 utc+8"))
        check("a place alone is no moment", "nil", at("tokyo") ?? "nil")
    }
}
