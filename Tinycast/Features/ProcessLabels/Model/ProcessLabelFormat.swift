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
        var path = components.path.replacing(#/\/{2,}/#, with: "/")
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1" }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// The model list sits beside `/chat/completions`, as `<base>/models`.
    static func modelsEndpoint(from typed: String) -> URL? {
        endpoint(from: typed)?.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "models", directoryHint: .notDirectory)
    }

    /// Sorted, so the menu reads the same each time; nil when the reply is not a model list.
    static func models(fromReply data: Data) -> [String]? {
        guard let reply = try? JSONDecoder().decode(ModelList.self, from: data) else { return nil }
        return Set(reply.data.map(\.id))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Asked by the Settings Test button, so a working connection proves itself with some fun.
    static let testQuestions = [
        "In one sentence: would a Turing machine that walks into a bar ever halt?",
        "Write a haiku about an off-by-one error.",
        "In one sentence, defend tabs or spaces as a Vulcan would.",
        "In one sentence, explain the Kessel Run in under 12 parsecs to an annoyed physicist.",
        "In one sentence, what is the 43rd answer, now that 42 is taken?",
        "Write a limerick about a race condition, in at most five lines."
    ]

    static func body(for signature: ProcessSignature, model: String) -> Data {
        encode(
            ChatRequest(
                model: model,
                messages: [
                    .init(role: "system", content: instructions),
                    .init(role: "user", content: signature.text)
                ]))
    }

    static func body(asking question: String, model: String) -> Data {
        encode(ChatRequest(model: model, messages: [.init(role: "user", content: question)]))
    }

    /// Encoding plain strings into a fixed shape cannot fail.
    private static func encode(_ request: ChatRequest) -> Data {
        (try? JSONEncoder().encode(request)) ?? Data()
    }

    /// The whole text of the first choice, trimmed; nil when it is empty.
    static func answer(fromReply data: Data) -> String? {
        guard let reply = try? JSONDecoder().decode(ChatReply.self, from: data),
            let content = reply.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !content.isEmpty
        else { return nil }
        return content
    }

    /// The first non-empty line of the first choice, stripped of quotes and a final period.
    static func label(fromReply data: Data) -> String? {
        guard let content = answer(fromReply: data) else { return nil }
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

    private struct ModelList: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }
}
