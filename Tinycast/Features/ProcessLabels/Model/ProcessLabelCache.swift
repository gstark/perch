import Foundation

/// Labels the AI gave, keyed by signature text, so a process seen before never costs a request.
struct ProcessLabelCache: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let label: String
        let recorded: Date
    }

    static let capacity = 500

    private(set) var entries: [String: Entry] = [:]

    var count: Int { entries.count }

    func label(for signature: ProcessSignature) -> String? {
        entries[signature.text]?.label
    }

    /// Past capacity the oldest labels go first.
    mutating func record(_ label: String, for signature: ProcessSignature, at date: Date) {
        entries[signature.text] = Entry(label: label, recorded: date)
        guard entries.count > Self.capacity else { return }
        let oldest = entries.sorted { $0.value.recorded < $1.value.recorded }
            .prefix(entries.count - Self.capacity)
        for (key, _) in oldest { entries[key] = nil }
    }

    mutating func removeAll() {
        entries = [:]
    }
}
