import Foundation

/// Why a request to the AI service failed, worded for the Settings pane.
enum ProcessLabelFailure: Error, Equatable, Sendable {
    case unreachable(host: String)
    case rejected(status: Int)
    case malformedReply

    var message: String {
        switch self {
        case .unreachable(let host): return "Could not reach \(host)"
        case .rejected(let status) where status == 401 || status == 403:
            return "The service refused the token (HTTP \(status))"
        case .rejected(let status): return "The service answered HTTP \(status)"
        case .malformedReply: return "The reply held no answer"
        }
    }
}
