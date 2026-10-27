import Foundation

/// Asks an OpenAI-compatible chat endpoint what one process is.
enum ProcessLabelService {
    /// Cacheless, never `URLSession.shared`, so neither the request nor the reply lands on disk.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    nonisolated static func label(
        for signature: ProcessSignature, endpoint: URL, model: String, token: String?
    ) async throws(ProcessLabelFailure) -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = ProcessLabelFormat.body(for: signature, model: model)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .unreachable(host: endpoint.host() ?? endpoint.absoluteString)
        }
        guard let http = response as? HTTPURLResponse else { throw .malformedReply }
        guard http.statusCode == 200 else { throw .rejected(status: http.statusCode) }
        guard let label = ProcessLabelFormat.label(fromReply: data) else { throw .malformedReply }
        return label
    }
}
