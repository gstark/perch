import Foundation

/// One row of the Git Watch window: an at-risk repo, or an ignored path with what the scan last saw.
struct GitWatchEntry: Hashable, Sendable, Identifiable {
    let path: String
    /// Nil for an ignored path the last scan did not find.
    let repo: GitWatchRepo?
    let isIgnored: Bool

    var id: String { path }
    var name: String { URL(filePath: path).lastPathComponent }
}

extension GitWatchMachine {
    /// At-risk and just-pushed repos, then every ignored path, so an ignored one can come back.
    func entries(in report: GitWatchReport?, keeping pushed: Set<String> = []) -> [GitWatchEntry] {
        let repos = report?.repos ?? []
        let watched = repos
            .filter { $0.state.isAtRisk || pushed.contains($0.path) }
            .filter { !ignoredPaths.contains($0.path) }
            .map { GitWatchEntry(path: $0.path, repo: $0, isIgnored: false) }
        let ignored = ignoredPaths.sorted().map { path in
            GitWatchEntry(path: path, repo: repos.first { $0.path == path }, isIgnored: true)
        }
        return watched + ignored
    }
}
