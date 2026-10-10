import Foundation

/// A machine Git Watch scans. The host is its identity, and an empty host is this Mac.
struct GitWatchMachine: Codable, Hashable, Sendable, Identifiable {
    var host: String
    var roots: [String]
    /// Repo paths exactly as the scan prints them.
    var ignoredPaths: [String] = []

    var id: String { host }
    var isLocal: Bool { host.isEmpty }
    var displayName: String { isLocal ? "This Mac" : host }

    static let thisMac = GitWatchMachine(host: "", roots: ["~/dev"])

    /// This Mac first and once, then each remote host once; a host ssh could read as an option goes.
    static func normalize(_ machines: [GitWatchMachine]) -> [GitWatchMachine] {
        var seen: Set<String> = []
        var result: [GitWatchMachine] = []
        for var machine in machines {
            machine.host = machine.host.trimmingCharacters(in: .whitespaces)
            guard !machine.host.hasPrefix("-"), !machine.host.contains(where: \.isWhitespace),
                seen.insert(machine.host).inserted
            else { continue }
            result.append(machine)
        }
        if let local = result.firstIndex(where: \.isLocal) {
            result.insert(result.remove(at: local), at: 0)
        } else {
            result.insert(thisMac, at: 0)
        }
        return result
    }

    /// The process that reads `GitWatchScript` on stdin.
    var shellCommand: (executable: String, arguments: [String]) {
        isLocal
            ? ("/bin/sh", ["-s"])
            : ("/usr/bin/ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host, "sh -s"])
    }

    /// What the menu copies for a remote repo: a login shell that starts in the repo folder.
    func terminalCommand(for path: String) -> String {
        let remote = "cd \(GitWatchScript.quoted(path)) && exec \"$SHELL\" -l"
        return "ssh -t \(host) \(GitWatchScript.quoted(remote))"
    }
}
