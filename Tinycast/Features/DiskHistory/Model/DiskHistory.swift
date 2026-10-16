import Foundation

/// A span the history can be drawn over.
enum DiskHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, year, all

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .all: "All"
        }
    }

    var span: TimeInterval? {
        switch self {
        case .day: DiskHistory.day
        case .week: 7 * DiskHistory.day
        case .month: 30 * DiskHistory.day
        case .year: 365 * DiskHistory.day
        case .all: nil
        }
    }

    /// Long enough that a chart never draws more than a few hundred points.
    func bucket(spanning seconds: TimeInterval) -> TimeInterval {
        switch self {
        case .day, .week: DiskHistory.hour
        case .month: 6 * DiskHistory.hour
        case .year: DiskHistory.day
        case .all:
            max(1, (seconds / DiskHistory.maxPoints / DiskHistory.day).rounded(.up)) * DiskHistory.day
        }
    }
}

/// The change in used space between two points; positive means space was consumed.
struct DiskChange: Equatable, Sendable {
    var start: Date
    var end: Date
    var bytes: Int64
}

enum DiskHistory {
    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 24 * hour
    static let maxPoints: TimeInterval = 400

    /// One sample per clock hour, so a sleeping Mac leaves a gap rather than a burst on wake.
    static func isDue(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return hourIndex(last) != hourIndex(now)
    }

    /// The last sample in each bucket of the range; `samples` must be oldest first.
    static func points(_ samples: [DiskSample], over range: DiskHistoryRange, now: Date) -> [DiskSample] {
        let start = range.span.map { now.addingTimeInterval(-$0) } ?? samples.first?.date ?? now
        let bucket = range.bucket(spanning: now.timeIntervalSince(start))
        var points: [DiskSample] = []
        var lastKey: Int64?
        for sample in samples where sample.date >= start && sample.date <= now {
            let key = Int64((sample.date.timeIntervalSince1970 / bucket).rounded(.down))
            if key == lastKey {
                points[points.count - 1] = sample
            } else {
                points.append(sample)
                lastKey = key
            }
        }
        return points
    }

    static func changes(_ points: [DiskSample]) -> [DiskChange] {
        zip(points, points.dropFirst()).map {
            DiskChange(start: $0.date, end: $1.date, bytes: $1.used - $0.used)
        }
    }

    /// Nil until the range holds two samples, so a fresh history never claims a change of zero.
    static func usedChange(_ samples: [DiskSample], over range: DiskHistoryRange, now: Date) -> Int64? {
        let points = points(samples, over: range, now: now)
        guard let first = points.first, let last = points.last, points.count > 1 else { return nil }
        return last.used - first.used
    }

    private static func hourIndex(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / hour).rounded(.down))
    }
}
