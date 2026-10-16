import Foundation
import Observation

/// Every recorded sample, kept in memory and appended to a CSV file that only grows.
@MainActor
@Observable
final class DiskHistoryStore {
    private(set) var samples: [DiskSample] = []
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async {
        let url = fileURL
        let loaded = await Task.detached { Self.read(url) }.value
        samples = loaded.sorted { $0.date < $1.date }
    }

    @discardableResult
    func append(_ sample: DiskSample) async -> Bool {
        samples.append(sample)
        let url = fileURL
        return await Task.detached { Self.write(DiskSampleFormat.line(for: sample), to: url) }.value
    }

    private nonisolated static func read(_ url: URL) -> [DiskSample] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return DiskSampleFormat.samples(from: text)
    }

    private nonisolated static func write(_ line: String, to url: URL) -> Bool {
        let data = Data(line.utf8)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return (try? data.write(to: url, options: .atomic)) != nil
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }
}
