import Foundation

/// The OpenAI-compatible chat request that asks what a process is, and the reading of its reply.
enum ProcessLabelFormat {
    static let maxLabelLength = 60

    static let instructions = """
        You identify processes on a software developer's Mac for a CPU usage menu. \
        Reply with only a short label of at most six words that says what the process is doing. \
        When the arguments or working directory show a project folder, name it with its path, \
        as in "dev server in ~/dev/shop" or "test suite in ~/dev/api". \
        For a macOS system process, say what the service does, as in "Spotlight indexing". \
        Do not repeat the executable name. No quotes and no final period. \
        "<redacted>" and "#" hide values that do not matter.
        """

    /// A bare host gets `/v1`; anything short of `/chat/completions` gets it appended.
    static func endpoint(from typed: String) -> URL? {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        guard var components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            components.host?.isEmpty == false
        else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1" }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func body(for signature: ProcessSignature, model: String) -> Data {
        let request = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: instructions),
                .init(role: "user", content: signature.text)
            ])
        // Encoding plain strings into a fixed shape cannot fail.
        return (try? JSONEncoder().encode(request)) ?? Data()
    }

    /// The first non-empty line of the first choice, stripped of quotes and a final period.
    static func label(fromReply data: Data) -> String? {
        guard let reply = try? JSONDecoder().decode(ChatReply.self, from: data),
            let content = reply.choices.first?.message.content
        else { return nil }
        let line = content.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard var label = line?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()"))
        else { return nil }
        if label.hasSuffix(".") { label.removeLast() }
        label = label.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        guard label.count > maxLabelLength else { return label }
        return String(label.prefix(maxLabelLength - 1)) + "…"
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
    }

    private struct ChatReply: Decodable {
        struct Choice: Decodable {
            struct Content: Decodable {
                let content: String?
            }

            let message: Content
        }

        let choices: [Choice]
    }
}
