import Foundation

/// Every way a request to the host can fail, each with the line the panel shows for it.
enum ProxmoxFailure: Error, Equatable, Sendable {
    case notConfigured
    case invalidAddress
    case unreachable(host: String)
    case untrustedCertificate
    case certificateBlocked
    case tokenRefused
    case tokenLacksAccess
    case httpStatus(Int)
    case malformedReply
    case noNode

    var message: String {
        switch self {
        case .notConfigured: "Set the address, token ID and token secret in Settings › Proxmox."
        case .invalidAddress: "The address in Settings › Proxmox is not a valid URL."
        case .unreachable(let host): "Cannot reach \(host)."
        case .untrustedCertificate:
            "The host's certificate is not trusted. Trust it in Settings › Proxmox."
        case .certificateBlocked:
            "macOS blocks this host's certificate. Use its ts.net name or its LAN address."
        case .tokenRefused:
            "Proxmox refused the token. Use the full token ID, like root@pam!perch."
        case .tokenLacksAccess: "The API token cannot read the host. Give it the PVEAuditor role."
        case .httpStatus(let code): "Proxmox answered with HTTP \(code)."
        case .malformedReply: "Proxmox sent a reply Perch cannot read."
        case .noNode: "Proxmox listed no node."
        }
    }

    init(httpStatus code: Int) {
        switch code {
        case 401: self = .tokenRefused
        case 403: self = .tokenLacksAccess
        default: self = .httpStatus(code)
        }
    }
}
