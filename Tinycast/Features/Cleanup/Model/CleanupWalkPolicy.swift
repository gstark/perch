import Foundation

/// Which folders the walk enters and which entries date a project.
enum CleanupWalkPolicy {
    /// Scratch folders hold no projects; one Rails `tmp/storage` alone held 137,000 folders.
    private static let scratch: Set<String> = ["tmp"]
    /// Folders macOS shows as one item; the walk reads names only, so it cannot ask LaunchServices.
    private static let packageExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "kext", "photoslibrary", "playground", "plugin",
        "xcarchive", "xcassets", "xcodeproj", "xcworkspace",
    ]

    /// Hidden folders hold tool state, not projects, and a package is one opaque item.
    static func descends(into name: String) -> Bool {
        guard !name.hasPrefix("."), !scratch.contains(name) else { return false }
        guard let dot = name.lastIndex(of: ".") else { return true }
        return !packageExtensions.contains(String(name[name.index(after: dot)...]))
    }

    /// `git status` rewrites `.git`, so the last commit, in this file, dates a repository instead.
    static let commitLog = ".git/logs/HEAD"

    /// Finder rewrites `.DS_Store` on a visit, which would make every browsed project look active.
    static func dates(_ name: String) -> Bool {
        name != ".DS_Store" && name != ".git"
    }
}
