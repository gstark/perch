import Foundation

/// Why a request to the AI service failed, worded for the Settings pane.
enum ProcessLabelFailure: Error, Equatable, Sendable {
    case unreachable(host: String)
    case rejected(status: Int)
    case malformedReply
    /// A web app's page at the API path, as Open WebUI serves for `/v1`.
    case webPage

    var message: String {
        switch self {
        case .unreachable(let host): return "Could not reach \(host)"
        case .rejected(let status) where status == 401 || status == 403:
            return "The service refused the token (HTTP \(status))"
        case .rejected(let status): return "The service answered HTTP \(status)"
        case .malformedReply: return "The reply held no answer"
        case .webPage: return "The endpoint sent a web page, not an API reply. Check its path."
        }
    }
}
