import Foundation

/// What a process signature keeps and hides, how the endpoint is completed, and the label cache.
@main
@MainActor
struct ProcessLabelsTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        signatures()
        redaction()
        endpoints()
        replies()
        modelLists()
        testQuestions()
        cache()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static let home = "/Users/dev"

    static func signature(_ arguments: [String], cwd: String? = nil) -> ProcessSignature {
        ProcessSignature(
            facts: ProcessFacts(
                executable: "/opt/homebrew/bin/ruby", arguments: arguments,
                workingDirectory: cwd, parent: "zsh"),
            home: home)
    }

    static func signatures() {
        let rails = signature(["ruby", "bin/rails", "server", "-p", "3000"], cwd: "/Users/dev/shop")
        expect(
            rails.text == """
                executable: /opt/homebrew/bin/ruby
                arguments: ruby bin/rails server -p #
                working directory: ~/shop
                parent: zsh
                """,
            "a dev server reads as path, arguments, folder and parent: \(rails.text)")
        let otherPort = signature(
            ["ruby", "bin/rails", "server", "-p", "3001"], cwd: "/Users/dev/shop")
        expect(rails == otherPort, "a port change keeps the signature")
        let otherFolder = signature(
            ["ruby", "bin/rails", "server", "-p", "3000"], cwd: "/Users/dev/api")
        expect(rails != otherFolder, "another folder is another signature")
        expect(signature([], cwd: home).text.contains("working directory: ~\n"), "home itself is ~")
        expect(
            signature(["node", "/Users/devops/x.js"]).text.contains("/Users/devops/x.js"),
            "only the home folder itself becomes ~")
        let spaced = signature(["ruby", "a b.rb"])
        expect(spaced.text.contains("\"a b.rb\""), "a spaced argument is quoted")
        let long = signature(["ruby", String(repeating: "a/", count: 100)])
        expect(long.text.contains("…"), "a long argument is cut")
        let many = signature((0..<60).map { "arg\($0)" })
        expect(!many.text.contains("arg40"), "arguments past the cap are dropped")
    }

    static func redaction() {
        let flagged = signature(["tool", "--token", "hunter2", "--api-key=abc", "--verbose"])
        expect(!flagged.text.contains("hunter2"), "a value after a sensitive flag is hidden")
        expect(!flagged.text.contains("abc"), "a sensitive name=value is hidden")
        expect(flagged.text.contains("--api-key=<redacted>"), "the flag's name stays")
        expect(flagged.text.contains("--verbose"), "an ordinary flag stays")
        let env = signature(["env", "GITHUB_TOKEN=ghp", "PATH=/bin"])
        expect(!env.text.contains("ghp") && env.text.contains("PATH=/bin"), "env assignments")
        let url = signature(["psql", "postgres://admin:s3cret@db.local/app"])
        expect(
            !url.text.contains("s3cret") && url.text.contains("://<redacted>@db.local"),
            "a URL's user info is hidden: \(url.text)")
        let opaque = signature(["worker", "sk-proj1234abcd5678efgh9012ijkl"])
        expect(!opaque.text.contains("abcd"), "a long opaque token is hidden")
        let word = signature(["node", "--max-old-space-size-for-something"])
        expect(word.text.contains("--max-old-space"), "a long word without digits stays")
        let trailing = signature(["tool", "--password"])
        expect(trailing.text.hasSuffix("--password\nparent: zsh"), "a final sensitive flag stays")
        let followedByFlag = signature(["tool", "--auth", "--quiet"])
        expect(followedByFlag.text.contains("--quiet"), "a flag after a sensitive flag stays")
    }

    static func endpoints() {
        let cases: [(String, String?)] = [
            ("https://api.openai.com/v1", "https://api.openai.com/v1/chat/completions"),
            ("https://api.openai.com/v1/", "https://api.openai.com/v1/chat/completions"),
            ("https://api.openai.com", "https://api.openai.com/v1/chat/completions"),
            ("http://localhost:11434/v1", "http://localhost:11434/v1/chat/completions"),
            ("https://openrouter.ai/api/v1", "https://openrouter.ai/api/v1/chat/completions"),
            ("https://x.example//v1", "https://x.example/v1/chat/completions"),
            (
                " https://x.example/v1/chat/completions?a=1 ",
                "https://x.example/v1/chat/completions"
            ),
            ("ftp://x.example", nil),
            ("api.openai.com", nil),
            ("", nil)
        ]
        for (typed, expected) in cases {
            let url = ProcessLabelFormat.endpoint(from: typed)?.absoluteString
            expect(url == expected, "\(typed) → \(url ?? "nil"), wanted \(expected ?? "nil")")
        }
    }

    static func reply(_ content: String) -> Data {
        let escaped = content.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return Data(#"{"choices":[{"message":{"role":"assistant","content":"\#(escaped)"}}]}"#.utf8)
    }

    static func replies() {
        let label = ProcessLabelFormat.label(fromReply:)
        expect(label(reply("dev server in ~/shop")) == "dev server in ~/shop", "a plain label")
        expect(label(reply("\"test suite in ~/api.\"")) == "test suite in ~/api", "quotes, period")
        expect(label(reply("\n\nSpotlight indexing\nmore")) == "Spotlight indexing", "first line")
        expect(label(reply("(bundler install)")) == "bundler install", "parentheses")
        expect(label(reply("   ")) == nil, "an empty reply")
        expect(label(Data("{}".utf8)) == nil, "no choices")
        let long = label(reply(String(repeating: "x", count: 80)))
        expect(long?.count == ProcessLabelFormat.maxLabelLength, "a long label is cut")

        let body = ProcessLabelFormat.body(for: ProcessSignature(text: "sig"), model: "m")
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = json?["messages"] as? [[String: String]]
        expect(json?["model"] as? String == "m", "the body names the model")
        expect(messages?.map { $0["role"] ?? "" } == ["system", "user"], "system then user")
        expect(messages?.last?["content"] == "sig", "the user message is the signature")
    }

    static func modelLists() {
        let cases: [(String, String?)] = [
            ("https://api.openai.com/v1", "https://api.openai.com/v1/models"),
            ("http://192.168.0.238:8317", "http://192.168.0.238:8317/v1/models"),
            ("https://x.example/v1/chat/completions", "https://x.example/v1/models"),
            ("https://openrouter.ai/api/v1/", "https://openrouter.ai/api/v1/models"),
            ("", nil)
        ]
        for (typed, expected) in cases {
            let url = ProcessLabelFormat.modelsEndpoint(from: typed)?.absoluteString
            expect(url == expected, "models: \(typed) → \(url ?? "nil")")
        }
        let ids = #"[{"id":"gpt-5"},{"id":"claude-2"},{"id":"claude-10"},{"id":"gpt-5"}]"#
        let list = Data(#"{"data":\#(ids)}"#.utf8)
        expect(
            ProcessLabelFormat.models(fromReply: list) == ["claude-2", "claude-10", "gpt-5"],
            "models are sorted, numbers in order, and unique")
        expect(ProcessLabelFormat.models(fromReply: Data("{}".utf8)) == nil, "not a model list")
    }

    static func testQuestions() {
        expect(!ProcessLabelFormat.testQuestions.isEmpty, "there is a question to ask")
        let body = ProcessLabelFormat.body(asking: "why 42?", model: "m")
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = json?["messages"] as? [[String: String]]
        expect(messages?.count == 1 && messages?.first?["role"] == "user", "only a user message")
        expect(messages?.first?["content"] == "why 42?", "the user message is the question")
        let answer = ProcessLabelFormat.answer(fromReply: reply("  Line one.\nLine two.  "))
        expect(answer == "Line one.\nLine two.", "an answer keeps every line: \(answer ?? "nil")")
    }

    static func cache() {
        var cache = ProcessLabelCache()
        let first = ProcessSignature(text: "a")
        cache.record("one", for: first, at: Date(timeIntervalSince1970: 0))
        expect(cache.label(for: first) == "one", "a recorded label is found")
        expect(cache.label(for: ProcessSignature(text: "b")) == nil, "another signature misses")
        for index in 1...ProcessLabelCache.capacity {
            cache.record(
                "\(index)", for: ProcessSignature(text: "s\(index)"),
                at: Date(timeIntervalSince1970: Double(index)))
        }
        expect(cache.count == ProcessLabelCache.capacity, "the cache stays at capacity")
        expect(cache.label(for: first) == nil, "the oldest label goes first")
        let data = try? JSONEncoder().encode(cache)
        let decoded = data.flatMap { try? JSONDecoder().decode(ProcessLabelCache.self, from: $0) }
        expect(decoded == cache, "the cache round-trips through JSON")
        cache.removeAll()
        expect(cache.count == 0, "clearing empties it")
    }
}
