import Foundation

/// The history file format, the hourly schedule, bucketing per range, and the store's round trip.
@main
@MainActor
struct DiskHistoryTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    static func sample(_ offset: TimeInterval, available: Int64, total: Int64 = 1000) -> DiskSample {
        DiskSample(
            date: base.addingTimeInterval(offset), total: total, available: available,
            free: available - 10)
    }

    static func main() async {
        format()
        schedule()
        bucketing()
        changes()
        reader()
        await store()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func format() {
        let original = sample(0, available: 400)
        let line = DiskSampleFormat.line(for: original)
        expect(line == "1800000000,1000,400,390\n", "a sample writes as one CSV line")
        let text = line + "garbage\n1,2,3\n\n" + DiskSampleFormat.line(for: sample(60, available: 300))
        let parsed = DiskSampleFormat.samples(from: text)
        expect(parsed.count == 2, "malformed and blank lines are skipped")
        expect(parsed.first == original, "a line reads back as the sample it came from")
        expect(original.used == 600 && original.purgeable == 10, "used and purgeable derive")
    }

    static func schedule() {
        let hourStart = base
        expect(DiskHistory.isDue(last: nil, now: base), "the first sample is always due")
        expect(
            !DiskHistory.isDue(last: hourStart, now: hourStart.addingTimeInterval(3599)),
            "a second sample in the same clock hour is not due")
        expect(
            DiskHistory.isDue(last: hourStart.addingTimeInterval(3599), now: hourStart.addingTimeInterval(3600)),
            "the next clock hour is due, however close")
    }

    static func bucketing() {
        let hourly = (0..<(24 * 40)).map { sample(TimeInterval($0) * 3600, available: Int64(1000 - $0)) }
        let now = hourly.last!.date
        let day = DiskHistory.points(hourly, over: .day, now: now)
        expect(day.count == 25, "a day holds the hourly samples from 24 hours ago to now")
        let month = DiskHistory.points(hourly, over: .month, now: now)
        expect(month.count <= 30 * 4 + 1, "a month buckets into six-hour points")
        expect(month.last == hourly.last, "a bucket keeps its newest sample")
        let all = DiskHistory.points(hourly, over: .all, now: now)
        expect(all.count == 41, "40 days that start mid-day touch 41 day buckets")
        let decade = (0..<3650).map { sample(TimeInterval($0) * DiskHistory.day, available: 500) }
        let long = DiskHistory.points(decade, over: .all, now: decade.last!.date)
        expect(long.count <= 400, "a decade stays within the point budget")
        let future = DiskHistory.points(hourly, over: .all, now: hourly[10].date)
        expect(future.count == 1, "samples after now are left out")
    }

    static func changes() {
        let points = [sample(0, available: 500), sample(3600, available: 450), sample(7200, available: 470)]
        let deltas = DiskHistory.changes(points)
        expect(deltas.map(\.bytes) == [50, -20], "a change is the growth in used space")
        expect(deltas.first?.start == points[0].date && deltas.first?.end == points[1].date, "a change spans its interval")
        let now = points.last!.date
        expect(DiskHistory.usedChange(points, over: .week, now: now) == 30, "the week's change is net")
        expect(DiskHistory.usedChange([points[0]], over: .week, now: now) == nil, "one sample has no change")
    }

    static func reader() {
        let reading = DiskSpaceReader.read(at: base)
        expect(reading != nil, "the startup volume can be read")
        if let reading {
            expect(reading.total > 0 && reading.available <= reading.total, "the reading is sane")
        }
    }

    static func store() async {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "disk-history-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "disk-history.csv")

        let first = DiskHistoryStore(fileURL: url)
        await first.load()
        expect(first.samples.isEmpty, "a missing file loads as an empty history")
        let wroteFirst = await first.append(sample(3600, available: 300))
        let wroteSecond = await first.append(sample(0, available: 400))
        expect(wroteFirst && wroteSecond, "appends create the file and then extend it")

        let second = DiskHistoryStore(fileURL: url)
        await second.load()
        expect(second.samples.count == 2, "a new store reads every appended sample")
        expect(second.samples.first?.date == base, "loading sorts by date after a clock change")
    }
}
