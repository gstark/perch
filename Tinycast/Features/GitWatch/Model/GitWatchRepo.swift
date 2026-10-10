import Foundation

/// What a default branch holds that its remote does not. Raw values are the script's spellings.
enum GitWatchRepoState: String, Sendable {
    case ahead, noRemote, unpushed, clean, error

    var isAtRisk: Bool { self == .ahead || self == .noRemote || self == .unpushed }
}

struct GitWatchRepo: Hashable, Sendable {
    let path: String
    let branch: String
    let state: GitWatchRepoState
    /// Commits missing from the upstream; with no upstream at all, every commit on the branch.
    let commitCount: Int

    var name: String { URL(filePath: path).lastPathComponent }

    var summary: String {
        switch state {
        case .ahead: "\(branch) ↑\(commitCount)"
        case .noRemote: "\(branch), no remote"
        case .unpushed: "\(branch), never pushed"
        case .clean: branch
        case .error: "unreadable"
        }
    }
}
