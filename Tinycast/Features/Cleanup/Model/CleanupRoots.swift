import Foundation

/// The folders Cleanup walks, stored with `~` so settings.json reads the same on any Mac.
enum CleanupRoots {
    static func abbreviate(_ path: String, home: String) -> String {
        let trimmed = trimmed(path)
        guard trimmed == home || trimmed.hasPrefix(home + "/") else { return trimmed }
        return "~" + trimmed.dropFirst(home.count)
    }

    static func expand(_ path: String, home: String) -> String {
        let trimmed = trimmed(path)
        guard trimmed == "~" || trimmed.hasPrefix("~/") else { return trimmed }
        return home + trimmed.dropFirst()
    }

    /// Abbreviates every path and drops blanks and duplicates, keeping order.
    static func normalize(_ paths: [String], home: String) -> [String] {
        var seen = Set<String>()
        return paths.map { abbreviate($0, home: home) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Absolute paths to walk; a root inside another is already covered by it.
    static func walkable(_ paths: [String], home: String) -> [String] {
        let expanded = Set(paths.map { expand($0, home: home) }.filter { !$0.isEmpty })
        return expanded.filter { path in
            !expanded.contains { $0 != path && ($0 == "/" || path.hasPrefix($0 + "/")) }
        }
        .sorted()
    }

    private static func trimmed(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
