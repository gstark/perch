import Foundation

/// A process with secrets and run-to-run noise removed: the cache key, and exactly what is sent.
struct ProcessSignature: Hashable, Sendable {
    static let redacted = "<redacted>"
    private static let maxArguments = 40
    private static let maxArgumentLength = 120
    private static let sensitiveWords = [
        "token", "secret", "passw", "pwd", "apikey", "api-key", "api_key", "auth", "credential",
        "key"
    ]

    let text: String

    init(text: String) {
        self.text = text
    }

    init(facts: ProcessFacts, home: String) {
        let arguments = Self.redactValues(
            facts.arguments.prefix(Self.maxArguments).map { Self.clean($0, home: home) })
        var lines = [
            "executable: \(Self.clean(facts.executable, home: home))",
            "arguments: \(arguments.map(Self.quoted).joined(separator: " "))"
        ]
        if let directory = facts.workingDirectory {
            lines.append("working directory: \(Self.clean(directory, home: home))")
        }
        if let parent = facts.parent { lines.append("parent: \(parent)") }
        text = lines.joined(separator: "\n")
    }

    /// The value after a sensitive flag, or after `name=`, goes; the flag's name stays.
    private static func redactValues(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var hideNext = false
        for argument in arguments {
            if hideNext, !argument.hasPrefix("-") {
                result.append(redacted)
                hideNext = false
                continue
            }
            hideNext = false
            if let equals = argument.firstIndex(of: "="), isSensitive(argument[..<equals]) {
                result.append(String(argument[...equals]) + redacted)
            } else {
                hideNext = argument.hasPrefix("-") && isSensitive(argument[...])
                result.append(argument)
            }
        }
        return result
    }

    private static func isSensitive(_ name: Substring) -> Bool {
        let name = name.lowercased()
        return sensitiveWords.contains { name.contains($0) }
    }

    private static func clean(_ value: String, home: String) -> String {
        var value = value == home ? "~" : value.replacingOccurrences(of: home + "/", with: "~/")
        value = value.replacing(#/:\/\/[^\/@\s]+@/#, with: "://\(redacted)@")
        value = value.replacing(#/[A-Za-z0-9_+=\-]{24,}/#) { match in
            let run = match.output
            return run.contains(where: \.isNumber) && run.contains(where: \.isLetter)
                ? redacted : String(run)
        }
        // Ports, pids and timestamps vary per run but say nothing about what the process is.
        value = value.replacing(#/\d{3,}/#, with: "#")
        guard value.count > maxArgumentLength else { return value }
        return String(value.prefix(maxArgumentLength)) + "…"
    }

    private static func quoted(_ argument: String) -> String {
        argument.contains(" ") ? "\"\(argument)\"" : argument
    }
}
