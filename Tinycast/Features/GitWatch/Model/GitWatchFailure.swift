import Foundation

/// Why a scan or a push failed; after a failed scan the last report stays and reads as stale.
enum GitWatchFailure: Error, Equatable, Sendable {
    case launch
    case timedOut
    case exited(message: String)

    var message: String {
        switch self {
        case .launch: "The command could not start"
        case .timedOut: "The command took longer than a minute"
        case .exited(let stderr): Self.summary(of: stderr) ?? "The command failed"
        }
    }

    /// Git ends a failed push with hints, so its rejection or error line says more than the last.
    private static func summary(of stderr: String) -> String? {
        let lines = stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.first { $0.hasPrefix("! ") || $0.hasPrefix("fatal:") || $0.hasPrefix("error:") }
            ?? lines.last
    }
}
