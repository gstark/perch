import Foundation
import Synchronization

/// The host's leaf certificate as seen during a TLS handshake.
struct ProxmoxCertificate: Equatable, Sendable {
    let fingerprint: String
    /// True when macOS trusts it already, so no pin is needed.
    let isSystemTrusted: Bool
}

/// Reads the host over HTTPS, accepting a certificate macOS trusts or the one the user pinned.
enum ProxmoxService {
    /// Cacheless, never `URLSession.shared`, so no reply ever lands on disk.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    nonisolated static func snapshot(
        of connection: ProxmoxConnection
    ) async throws(ProxmoxFailure) -> ProxmoxSnapshot {
        var request = URLRequest(url: connection.resourcesURL)
        request.setValue(connection.authorization, forHTTPHeaderField: "Authorization")
        let trust = TrustDelegate(pinnedFingerprint: connection.pinnedFingerprint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: trust)
        } catch {
            if trust.rejected { throw .untrustedCertificate }
            // App Transport Security refuses some hosts even after the pin accepts the certificate.
            if trust.seen != nil, (error as? URLError)?.code == .secureConnectionFailed {
                throw .certificateBlocked
            }
            throw .unreachable(host: connection.baseURL.host() ?? connection.baseURL.absoluteString)
        }
        guard let http = response as? HTTPURLResponse else { throw .malformedReply }
        guard http.statusCode == 200 else { throw ProxmoxFailure(httpStatus: http.statusCode) }
        return try ProxmoxFeed.snapshot(resources: data)
    }

    /// Completes only the handshake: the reply is ignored, so no token is sent.
    nonisolated static func certificate(at baseURL: URL) async throws(ProxmoxFailure)
        -> ProxmoxCertificate
    {
        let trust = TrustDelegate(pinnedFingerprint: nil)
        _ = try? await session.data(for: URLRequest(url: baseURL), delegate: trust)
        guard let seen = trust.seen else {
            throw .unreachable(host: baseURL.host() ?? baseURL.absoluteString)
        }
        return seen
    }
}

/// One request's trust decision; it records what it saw so a caller can explain a rejection.
private final class TrustDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let pinnedFingerprint: String?
    private let state = Mutex<(seen: ProxmoxCertificate?, rejected: Bool)>((nil, false))

    init(pinnedFingerprint: String?) {
        self.pinnedFingerprint = pinnedFingerprint
    }

    var seen: ProxmoxCertificate? { state.withLock { $0.seen } }
    var rejected: Bool { state.withLock { $0.rejected } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = space.serverTrust
        else { return (.performDefaultHandling, nil) }
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            state.withLock { $0.rejected = true }
            return (.cancelAuthenticationChallenge, nil)
        }
        let certificate = ProxmoxCertificate(
            fingerprint: ProxmoxConnection.fingerprint(of: SecCertificateCopyData(leaf) as Data),
            isSystemTrusted: SecTrustEvaluateWithError(trust, nil))
        let accepted =
            certificate.isSystemTrusted || certificate.fingerprint == pinnedFingerprint
        state.withLock {
            $0.seen = certificate
            $0.rejected = !accepted
        }
        guard accepted else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
