import CryptoKit
import Foundation

/// Everything one request needs, read fresh from settings and the Keychain for each refresh.
struct ProxmoxConnection: Equatable, Sendable {
    static let defaultPort = 8006

    let baseURL: URL
    let tokenID: String
    let secret: String
    /// The leaf certificate's SHA-256 the user confirmed; nil trusts only what macOS trusts.
    let pinnedFingerprint: String?

    var resourcesURL: URL { baseURL.appending(path: "api2/json/cluster/resources") }

    var authorization: String { "PVEAPIToken=\(tokenID)=\(secret)" }

    /// A bare host gets Proxmox's port; only `https`, since App Transport Security blocks `http`.
    static func baseURL(from address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasScheme = trimmed.contains("://")
        guard var components = URLComponents(string: hasScheme ? trimmed : "https://" + trimmed),
            components.scheme == "https",
            let host = components.host, !host.isEmpty
        else { return nil }
        if !hasScheme, components.port == nil { components.port = defaultPort }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Colon-separated uppercase hex, the form the Proxmox web UI shows under Certificates.
    static func fingerprint(of certificate: Data) -> String {
        SHA256.hash(data: certificate).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
