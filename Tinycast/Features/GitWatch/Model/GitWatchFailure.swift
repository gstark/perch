import Foundation

/// Why a machine's scan produced no report; the last report stays and reads as stale.
enum GitWatchFailure: Error, Equatable, Sendable {
    case launch
    case timedOut
    case exited(message: String)

    var message: String {
        switch self {
        case .launch: "The scan could not start"
        case .timedOut: "The scan took longer than a minute"
        case .exited(let message): message.isEmpty ? "The scan failed" : message
        }
    }
}
