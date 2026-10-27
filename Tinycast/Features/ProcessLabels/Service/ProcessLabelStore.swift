import Foundation
import Observation

/// The label cache, held in memory and rewritten as one JSON file after each change.
@MainActor
@Observable
final class ProcessLabelStore {
    private(set) var cache = ProcessLabelCache()
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async {
        let url = fileURL
        cache = await Task.detached { Self.read(url) }.value
    }

    func label(for signature: ProcessSignature) -> String? {
        cache.label(for: signature)
    }

    @discardableResult
    func record(_ label: String, for signature: ProcessSignature, at date: Date) async -> Bool {
        cache.record(label, for: signature, at: date)
        return await save()
    }

    @discardableResult
    func removeAll() async -> Bool {
        cache.removeAll()
        return await save()
    }

    private func save() async -> Bool {
        let snapshot = cache
        let url = fileURL
        return await Task.detached { Self.write(snapshot, to: url) }.value
    }

    private nonisolated static func read(_ url: URL) -> ProcessLabelCache {
        guard let data = try? Data(contentsOf: url),
            let cache = try? JSONDecoder().decode(ProcessLabelCache.self, from: data)
        else { return ProcessLabelCache() }
        return cache
    }

    private nonisolated static func write(_ cache: ProcessLabelCache, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(cache) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
