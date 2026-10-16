import Foundation

/// Reads the startup volume's capacity; APFS volumes share a container, so `/` speaks for them all.
enum DiskSpaceReader {
    /// The important-usage figure can take a moment to compute, so callers stay off the main actor.
    nonisolated static func read(volume: URL = URL(filePath: "/"), at date: Date) -> DiskSample? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? volume.resourceValues(forKeys: keys),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage,
            let free = values.volumeAvailableCapacity
        else { return nil }
        return DiskSample(date: date, total: Int64(total), available: available, free: Int64(free))
    }
}
