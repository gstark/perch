import Foundation

/// Talks to an OpenAI-compatible service: labels a process, lists models, answers a test question.
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
        let body = ProcessLabelFormat.body(for: signature, model: model)
        let data = try await send(endpoint, body: body, token: token)
        guard let label = ProcessLabelFormat.label(fromReply: data) else { throw .malformedReply }
        return label
    }

    nonisolated static func answer(
        to question: String, endpoint: URL, model: String, token: String?
    ) async throws(ProcessLabelFailure) -> String {
        let body = ProcessLabelFormat.body(asking: question, model: model)
        let data = try await send(endpoint, body: body, token: token)
        guard let answer = ProcessLabelFormat.answer(fromReply: data) else {
            throw .malformedReply
        }
        return answer
    }

    nonisolated static func models(
        endpoint: URL, token: String?
    ) async throws(ProcessLabelFailure) -> [String] {
        let data = try await send(endpoint, body: nil, token: token)
        guard let models = ProcessLabelFormat.models(fromReply: data) else {
            throw .malformedReply
        }
        return models
    }

    /// A POST when there is a body, otherwise a GET.
    private nonisolated static func send(
        _ endpoint: URL, body: Data?, token: String?
    ) async throws(ProcessLabelFailure) -> Data {
        var request = URLRequest(url: endpoint)
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .unreachable(host: endpoint.host() ?? endpoint.absoluteString)
        }
        guard let http = response as? HTTPURLResponse else { throw .malformedReply }
        guard http.statusCode == 200 else { throw .rejected(status: http.statusCode) }
        guard http.mimeType != "text/html" else { throw .webPage }
        return data
    }
}
