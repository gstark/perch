import Foundation

/// One reading of the startup volume, in bytes.
struct DiskSample: Equatable, Sendable {
    var date: Date
    var total: Int64
    /// What Finder reports: free space plus what macOS can purge on demand.
    var available: Int64
    var free: Int64

    var used: Int64 { total - available }
    var purgeable: Int64 { max(0, available - free) }
}

/// The history file: one `epoch,total,available,free` line per sample, oldest first.
enum DiskSampleFormat {
    static func line(for sample: DiskSample) -> String {
        let epoch = Int64(sample.date.timeIntervalSince1970.rounded())
        return "\(epoch),\(sample.total),\(sample.available),\(sample.free)\n"
    }

    /// A torn or hand-edited line is skipped rather than failing the whole file.
    static func samples(from text: String) -> [DiskSample] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: ",").compactMap { Int64($0) }
            guard fields.count == 4 else { return nil }
            return DiskSample(
                date: Date(timeIntervalSince1970: TimeInterval(fields[0])),
                total: fields[1], available: fields[2], free: fields[3])
        }
    }
}
