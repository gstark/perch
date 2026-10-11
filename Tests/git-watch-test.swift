import Foundation

/// The scan output parser, machine normalisation, shell quoting, and the script against real repos.
@main
@MainActor
struct GitWatchTests {
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

    static func main() async {
        parsing()
        machines()
        quoting()
        await scanning()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func parsing() {
        let output = """
            repo\t/home/g/dev/a b\tmain\tahead\t3
            repo\t/x\t\tclean\t0
            missingRoot\t/gone
            repo\t/y\tmain\tbogus\t1
            nonsense

            """
        let report = GitWatchReport(parsing: output)
        expect(report.repos.count == 2, "two well-formed repo lines")
        expect(
            report.repos.first
                == GitWatchRepo(path: "/home/g/dev/a b", branch: "main", state: .ahead, commitCount: 3),
            "a path with a space survives")
        expect(report.repos.first?.name == "a b", "the name is the folder name")
        expect(report.missingRoots == ["/gone"], "a missing root is reported")
        expect(report.unparsedLineCount == 2, "an unknown state and a stray line are counted")
        expect(report.atRisk.map(\.path) == ["/home/g/dev/a b"], "only the ahead repo is at risk")
        expect(
            GitWatchRepoState.ahead.isAtRisk && GitWatchRepoState.unpushed.isAtRisk
                && !GitWatchRepoState.noRemote.isAtRisk && !GitWatchRepoState.clean.isAtRisk
                && !GitWatchRepoState.error.isAtRisk,
            "only ahead and unpushed are at risk; a repo with no remote has nowhere to push")
        expect(
            GitWatchFailure.exited(message: "").message == "The command failed"
                && GitWatchFailure.exited(message: "No route\n").message == "No route",
            "an exit with no stderr still says something")
        let rejected = """
            To github.com:g/perch.git
             ! [rejected]        main -> main (fetch first)
            error: failed to push some refs to 'github.com:g/perch.git'
            hint: Updates were rejected because the remote contains work that you do not
            """
        expect(
            GitWatchFailure.exited(message: rejected).message
                == "! [rejected]        main -> main (fetch first)",
            "a push failure shows git's rejection line, not the last hint")

        var marked = report
        marked.markClean("/home/g/dev/a b")
        expect(marked.atRisk.isEmpty, "a pushed repo stops counting at once")
        expect(marked.repos.first?.state == .clean, "the pushed repo reads as clean")
    }

    static func machines() {
        let normal = GitWatchMachine.normalize([
            GitWatchMachine(host: " nas ", roots: ["~/dev"]),
            GitWatchMachine(host: "nas", roots: ["/srv"]),
            GitWatchMachine(host: "-oProxyCommand=x", roots: []),
            GitWatchMachine(host: "two words", roots: []),
            GitWatchMachine(host: "", roots: ["~/code"])
        ])
        expect(normal.map(\.host) == ["", "nas"], "this Mac first, one per host, unsafe hosts dropped")
        expect(normal.first?.roots == ["~/code"], "an existing local machine keeps its roots")
        expect(normal.last?.roots == ["~/dev"], "the first entry for a host wins")
        expect(GitWatchMachine.normalize([]) == [.thisMac], "an empty list gains this Mac")
        expect(GitWatchMachine.thisMac.displayName == "This Mac", "the local machine has a name")

        let report = GitWatchReport(parsing: """
            repo\t/d/b\tmain\tahead\t1
            repo\t/d/a\tmain\tunpushed\t2
            repo\t/d/c\tmain\tclean\t0
            repo\t/d/x\tmain\tahead\t4

            """)
        let ignoring = GitWatchMachine(host: "", roots: [], ignoredPaths: ["/d/x", "/d/gone"])
        let entries = ignoring.entries(in: report)
        expect(
            entries.map(\.path) == ["/d/a", "/d/b", "/d/gone", "/d/x"],
            "at-risk repos first, then every ignored path, each group sorted")
        expect(
            entries.map(\.isIgnored) == [false, false, true, true], "ignored entries are marked")
        expect(entries[3].repo?.commitCount == 4, "an ignored repo still found keeps its state")
        expect(entries[2].repo == nil, "an ignored repo the scan no longer finds has no state")
        expect(ignoring.entries(in: nil).map(\.path) == ["/d/gone", "/d/x"], "before a scan")
        let kept = ignoring.entries(in: report, keeping: ["/d/c"]).map(\.path)
        expect(kept.prefix(3) == ["/d/a", "/d/b", "/d/c"], "a just-pushed repo stays listed")
    }

    static func quoting() {
        expect(GitWatchScript.quoted("it's") == #"'it'\''s'"#, "a quote is closed, escaped, reopened")
        let nas = GitWatchMachine(host: "nas", roots: [])
        expect(
            nas.terminalCommand(for: "/srv/a b")
                == #"ssh -t nas 'cd '\''/srv/a b'\'' && exec "$SHELL" -l'"#,
            "the copied command opens a shell in the repo folder")
        expect(
            nas.shellCommand.executable == "/usr/bin/ssh"
                && nas.shellCommand.arguments.contains("BatchMode=yes"),
            "a remote scan can never prompt")
        expect(GitWatchMachine.thisMac.shellCommand.executable == "/bin/sh", "this Mac runs sh itself")
        let script = GitWatchScript.make(roots: ["~/dev", "/tmp/it's"])
        expect(script.contains("scan_root '~/dev'"), "a root is passed quoted, so the script expands ~")
        expect(script.contains(#"scan_root '/tmp/it'\''s'"#), "a root with a quote stays one word")
        expect(script.hasSuffix("exit 0\n"), "only a transport failure can exit non-zero")
    }

    static func scanning() async {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "git-watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ arguments: String..., in folder: String? = nil) {
            run(arguments, in: folder.map { root.appending(path: $0) } ?? root)
        }

        git("init", "-q", "--bare", "-b", "main", "remote.git")
        git("init", "-q", "-b", "main", "a b ahead")
        git("commit", "-q", "--allow-empty", "-m", "1", in: "a b ahead")
        git("remote", "add", "origin", "../remote.git", in: "a b ahead")
        git("push", "-q", "-u", "origin", "main", in: "a b ahead")
        git("commit", "-q", "--allow-empty", "-m", "2", in: "a b ahead")
        git("commit", "-q", "--allow-empty", "-m", "3", in: "a b ahead")
        git("init", "-q", "-b", "main", "loose")
        git("commit", "-q", "--allow-empty", "-m", "1", in: "loose")
        git("init", "-q", "-b", "main", "never")
        git("commit", "-q", "--allow-empty", "-m", "1", in: "never")
        git("init", "-q", "--bare", "-b", "main", "never.git")
        git("remote", "add", "origin", "../never.git", in: "never")
        git("clone", "-q", "remote.git", "synced")
        git("init", "-q", "-b", "main", "node_modules/dep")
        git("commit", "-q", "--allow-empty", "-m", "1", in: "node_modules/dep")
        git("init", "-q", "--bare", "-b", "trunk", "trunk.git")
        git("init", "-q", "-b", "trunk", "seed")
        git("commit", "-q", "--allow-empty", "-m", "1", in: "seed")
        git("push", "-q", "../trunk.git", "trunk", in: "seed")
        git("clone", "-q", "trunk.git", "trunk clone")
        git("commit", "-q", "--allow-empty", "-m", "2", in: "trunk clone")

        let missing = root.appending(path: "missing").path
        let machine = GitWatchMachine(host: "", roots: [root.path, missing])
        guard case .success(let report) = await GitWatchScanner.scan(machine) else {
            expect(false, "a local scan succeeds")
            return
        }
        func summary(_ name: String) -> String? {
            report.repos.first { $0.name == name }
                .map { "\($0.branch) \($0.state.rawValue) \($0.commitCount)" }
        }
        expect(summary("a b ahead") == "main ahead 2", "commits after the push are ahead")
        expect(summary("loose") == "main noRemote 1", "a repo with no remote is flagged")
        expect(summary("never") == "main unpushed 1", "a remote with no pushed branch is flagged")
        expect(summary("synced") == "main clean 0", "a fresh clone is clean")
        expect(summary("seed") == "trunk noRemote 1", "the checked-out branch is the last fallback")
        expect(summary("trunk clone") == "trunk ahead 1", "origin/HEAD names the default branch")
        expect(!report.repos.contains { $0.path.contains("node_modules") }, "node_modules is skipped")
        expect(report.missingRoots == [missing], "a missing root is reported and the scan goes on")
        expect(report.unparsedLineCount == 0, "every line parses")

        for name in ["a b ahead", "never"] {
            let path = root.appending(path: name).path
            let pushed = await GitWatchShell.run(GitWatchScript.push(path: path, branch: "main"), on: machine)
            if case .failure(let failure) = pushed { expect(false, "push \(name): \(failure.message)") }
        }
        guard case .success(let after) = await GitWatchScanner.scan(machine) else {
            expect(false, "the scan after the push succeeds")
            return
        }
        let names = Set(after.atRisk.map(\.name))
        expect(!names.contains("a b ahead"), "a push to the upstream clears an ahead repo")
        expect(!names.contains("never"), "a first push sets the upstream and clears an unpushed repo")
        let blocked = root.appending(path: "synced").path
        git("commit", "-q", "--allow-empty", "-m", "theirs", in: "a b ahead")
        git("push", "-q", in: "a b ahead")
        git("commit", "-q", "--allow-empty", "-m", "mine", in: "synced")
        let rejected = await GitWatchShell.run(GitWatchScript.push(path: blocked, branch: "main"), on: machine)
        guard case .failure(let failure) = rejected else {
            expect(false, "a push that is not a fast-forward fails")
            return
        }
        expect(failure.message.contains("rejected"), "a rejected push says so: \(failure.message)")
    }

    static func run(_ arguments: [String], in folder: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
            "GIT_CONFIG_GLOBAL": "/dev/null"
        ]) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.runObservingExit().wait()
        } catch {
            expect(false, "git \(arguments.joined(separator: " ")) launches")
            return
        }
        expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " ")) succeeds")
    }
}
