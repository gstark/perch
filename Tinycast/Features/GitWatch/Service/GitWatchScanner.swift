import Foundation

/// Runs `GitWatchScript` on one machine and parses what it prints.
nonisolated enum GitWatchScanner {
    static func scan(
        _ machine: GitWatchMachine, timeout: Duration = .seconds(60)
    ) async -> Result<GitWatchReport, GitWatchFailure> {
        await GitWatchShell.run(GitWatchScript.make(roots: machine.roots), on: machine, timeout: timeout)
            .map(GitWatchReport.init(parsing:))
    }
}
