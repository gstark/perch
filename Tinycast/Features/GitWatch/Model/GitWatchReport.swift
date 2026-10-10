import Foundation

/// One machine's scan, parsed from the tab-separated lines `GitWatchScript` prints.
struct GitWatchReport: Equatable, Sendable {
    var repos: [GitWatchRepo] = []
    var missingRoots: [String] = []
    var unparsedLineCount = 0

    init(parsing output: String) {
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch fields.first {
            case "repo"? where fields.count == 5:
                guard let state = GitWatchRepoState(rawValue: fields[3]), let count = Int(fields[4])
                else {
                    unparsedLineCount += 1
                    continue
                }
                repos.append(
                    GitWatchRepo(path: fields[1], branch: fields[2], state: state, commitCount: count))
            case "missingRoot"? where fields.count == 2:
                missingRoots.append(fields[1])
            default:
                unparsedLineCount += 1
            }
        }
        repos.sort { $0.path < $1.path }
    }

    var atRisk: [GitWatchRepo] { repos.filter(\.state.isAtRisk) }
}
