import Foundation
import Synchronization

/// Project kinds, the walk rules, roots, the age filter, and a real scan of a scratch tree.
@main
@MainActor
struct CleanupTests {
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

    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let calendar = Calendar(identifier: .gregorian)

    static func main() async {
        kinds()
        walkPolicy()
        roots()
        age()
        removalPolicy()
        do {
            try await scan()
            try removal()
        } catch {
            expect(false, "the scratch tree builds: \(error)")
        }
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func kinds() {
        func kinds(_ files: Set<String>, _ folders: Set<String> = []) -> [CleanupProjectKind] {
            CleanupProjectKind.kinds(fileNames: files, directoryNames: folders)
        }
        expect(kinds(["package.json"]) == [.node], "package.json marks a Node project")
        expect(kinds(["README.md", "Gemfile"]).isEmpty, "a folder with no marker is no project")
        expect(
            kinds(["package.json"], ["ios"]) == [.reactNative],
            "an ios folder makes a Node project React Native")
        expect(
            kinds(["Cargo.toml", "build.py"]) == [.cargo, .python],
            "a folder can be more than one kind")
        expect(
            kinds(["Game.csproj", "project.godot"]) == [.godot],
            "a Godot project's .csproj is not a .NET project")
        expect(kinds(["App.fsproj"]) == [.dotnet], "an .fsproj marks .NET")
        expect(
            CleanupProjectKind.artifacts(of: [.gradle, .cmake])
                == ["build", ".gradle", "cmake-build-debug", "cmake-build-release"],
            "a build folder two kinds share is listed once")
    }

    static func walkPolicy() {
        expect(CleanupWalkPolicy.descends(into: "src"), "a plain folder is entered")
        expect(CleanupWalkPolicy.descends(into: "v1.2"), "a dotted name that is no package too")
        expect(!CleanupWalkPolicy.descends(into: ".git"), "a hidden folder is not")
        expect(!CleanupWalkPolicy.descends(into: "App.xcodeproj"), "nor a package")
        expect(!CleanupWalkPolicy.descends(into: "tmp"), "nor a scratch folder")
        expect(!CleanupWalkPolicy.dates(".DS_Store"), "Finder's .DS_Store does not date a project")
        expect(CleanupWalkPolicy.dates("main.swift"), "a source file does")
    }

    static func roots() {
        let home = "/Users/me"
        expect(
            CleanupRoots.normalize(["/Users/me/dev/", "~/dev", " ", "/opt/src"], home: home)
                == ["~/dev", "/opt/src"],
            "roots abbreviate, trim, and drop blanks and duplicates")
        expect(CleanupRoots.abbreviate("/Users/meh", home: home) == "/Users/meh", "a prefix is no home")
        expect(CleanupRoots.expand("~/dev", home: home) == "/Users/me/dev", "~ expands to home")
        expect(
            CleanupRoots.walkable(["~/dev/personal", "~/dev", "~/devices"], home: home)
                == ["/Users/me/dev", "/Users/me/devices"],
            "a root inside another root is walked once, by the outer one")
    }

    static func age() {
        func project(_ path: String, bytes: Int64, monthsOld: Int) -> CleanupProject {
            CleanupProject(
                path: path, kinds: [.node],
                artifacts: [CleanupArtifact(name: "node_modules", bytes: bytes, sharedBytes: 1)],
                lastModified: calendar.date(byAdding: .month, value: -monthsOld, to: now)!
                    .addingTimeInterval(-60))
        }
        let report = CleanupReport(
            projects: [
                project("/b", bytes: 10, monthsOld: 0), project("/a", bytes: 10, monthsOld: 4),
                project("/c", bytes: 50, monthsOld: 12),
            ],
            unreadable: [], date: now)
        let all = CleanupAge.any.projects(in: report, now: now, calendar: calendar)
        expect(all.map(\.path) == ["/c", "/a", "/b"], "the most space first, then by path")
        let old = CleanupAge.threeMonths.projects(in: report, now: now, calendar: calendar)
        expect(old.map(\.path) == ["/c", "/a"], "three months leaves out a project changed today")
        let year = CleanupAge.oneYear.projects(in: report, now: now, calendar: calendar)
        expect(year.map(\.path) == ["/c"], "a project just over a year old passes one year")
        expect(all.first?.reclaimable == 49, "shared bytes do not count as reclaimable")
    }

    static func scan() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "cleanup-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        func file(_ path: String, bytes: Int = 1, modified: Date? = nil) throws {
            let url = root.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: url)
            if let modified { try fm.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        }

        let old = calendar.date(byAdding: .year, value: -2, to: .now)!
        // The stray marker that hid a whole folder of projects from kondo.
        try file("personal/package.json")
        try file("personal/app/package.json")
        try file("personal/app/node_modules/big.bin", bytes: 100_000)
        try file("personal/app/node_modules/dep/package.json")
        try file("personal/app/spa/package.json")
        try file("personal/app/spa/node_modules/x.bin", bytes: 20_000)
        try file("personal/tool/Package.swift")
        try file("personal/tool/.build/own.bin", bytes: 30_000)
        try file("store/linked.bin", bytes: 40_000)
        try fm.linkItem(
            at: root.appending(path: "store/linked.bin"),
            to: root.appending(path: "personal/tool/.build/linked.bin"))
        try file("personal/mobile/package.json")
        try file("personal/mobile/ios/Podfile")
        try file("personal/mobile/ios/Pods/pod.bin", bytes: 10_000)
        try file("personal/.hidden/package.json")
        try file("personal/.hidden/node_modules/x.bin")
        try file("personal/linked/package.json")
        try fm.createSymbolicLink(
            at: root.appending(path: "personal/linked/node_modules"),
            withDestinationURL: root.appending(path: "store"))
        try file("old/Cargo.toml", modified: old)
        try file("old/target/fresh.bin", bytes: 5_000)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: root.appending(path: "old").path)

        let now = Self.now
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let last = Mutex<CleanupProgress?>(nil)
        let report = await Task.detached {
            await CleanupScanner.scan(roots: [root], now: now) { progress in
                last.withLock { $0 = progress }
            }
        }.value
        guard let report else { return expect(false, "an uncancelled scan finishes") }
        let final = last.withLock { $0 }
        expect(
            final?.isSizing == true && final?.foldersSized == final?.foldersToSize
                && final?.foldersToSize == 5 && final?.projectsFound == 5,
            "progress ends with every build folder sized: \(String(describing: final))")
        let byPath = Dictionary(
            uniqueKeysWithValues: report.projects.map {
                (String($0.path.dropFirst(rootPath.count + 1)), $0)
            })

        expect(
            Set(byPath.keys)
                == ["personal/app", "personal/app/spa", "personal/tool", "personal/mobile", "old"],
            "the walk goes past a stray marker and into nested projects: \(byPath.keys.sorted())")
        expect(byPath["personal"] == nil, "a project with no build folder is not listed")
        expect(byPath["personal/linked"] == nil, "a symlinked build folder is not claimed")
        expect(
            byPath["personal/app"]?.artifacts.map(\.name) == ["node_modules"]
                && byPath["personal/app"].map { $0.reclaimable >= 100_000 } == true,
            "a project's build folder is sized by what it allocates")
        expect(
            byPath["personal/app"].map { $0.reclaimable < 120_000 } == true,
            "a nested project's build folder is not counted in its parent")
        let mobile = byPath["personal/mobile"]
        expect(
            mobile?.kinds == [.reactNative] && mobile?.artifacts.map(\.name) == ["ios/Pods"],
            "a React Native project claims ios/Pods")
        expect(byPath["personal/mobile/ios"] == nil, "so the Podfile under it is no second project")
        let tool = byPath["personal/tool"]?.artifacts.first
        expect(
            tool.map { $0.sharedBytes >= 40_000 && $0.reclaimable >= 30_000 } == true,
            "a hard-linked file counts as shared, not reclaimable")
        expect(
            byPath["old"].map { abs($0.lastModified.timeIntervalSince(old)) < 1 } == true,
            "a fresh file in a build folder does not make a project look active")
        expect(report.unreadable.isEmpty, "every scratch folder is readable")
        expect(
            report.projects.firstIndex { $0.path.hasSuffix("/personal/app") }!
                < report.projects.firstIndex { $0.path.hasSuffix("/personal/app/spa") }!,
            "a parent project comes before the project nested in it")

        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return await CleanupScanner.scan(roots: [root], now: now)
        }
        expect(await cancelled.value == nil, "a cancelled scan reports nothing")
    }

    static func removalPolicy() {
        func target(_ project: String, _ name: String) -> CleanupRemovalTarget {
            CleanupRemovalTarget(projectPath: project, name: name)
        }
        expect(CleanupRemovalPolicy.isSafe(target("/Users/me/app", "node_modules")), "a build folder is safe")
        expect(CleanupRemovalPolicy.isSafe(target("/Users/me/rn", "ios/Pods")), "so is a nested one")
        expect(!CleanupRemovalPolicy.isSafe(target("/Users/me/app", "src")), "a source folder is not")
        expect(!CleanupRemovalPolicy.isSafe(target("Users/me/app", "target")), "nor a relative project")
        expect(!CleanupRemovalPolicy.isSafe(target("/", "target")), "nor the volume root")
        expect(!CleanupRemovalPolicy.isSafe(target("/Users/me/../me", "target")), "nor a path that climbs")
        expect(!CleanupRemovalPolicy.isSafe(target("/Users//me", "target")), "nor an empty step")

        func project(_ path: String, _ names: [String]) -> CleanupProject {
            CleanupProject(
                path: path, kinds: [.node],
                artifacts: names.map { CleanupArtifact(name: $0, bytes: 100, sharedBytes: 10) },
                lastModified: now)
        }
        let report = CleanupReport(
            projects: [project("/a", ["node_modules", ".angular"]), project("/b", ["node_modules"])],
            unreadable: [], date: now)
        let targets = CleanupRemovalPolicy.targets(for: report.projects)
        expect(targets.count == 3, "every build folder of every project is a target")
        let gone = [target("/a", "node_modules"), target("/b", "node_modules")]
        expect(
            CleanupRemovalPolicy.reclaimable(of: gone, in: report) == 180,
            "the space a removal frees is the targets' reclaimable bytes")
        let after = CleanupRemovalPolicy.report(report, without: gone)
        expect(
            after.projects.map(\.path) == ["/a"]
                && after.projects.first?.artifacts.map(\.name) == [".angular"],
            "a removed folder leaves the report, and a project with none left goes too")

        let one = CleanupRemovalQuestion(
            projects: [report.projects[0]], folders: 2, bytes: 2_000_000_000, mode: .trash)
        expect(one.title == "Move build folders to the Trash?", "one project's title")
        expect(
            one.message.hasPrefix("node_modules, .angular, 2 GB.") && one.message.contains("empty the Trash"),
            "one project names its folders and says when the space comes back: \(one.message)")
        let many = CleanupRemovalQuestion(
            projects: report.projects, folders: 3, bytes: 300, mode: .delete)
        expect(many.title == "Delete build folders of 2 projects?", "many projects' title")
        expect(
            many.message.hasPrefix("3 folders,") && many.message.hasSuffix("This can't be undone."),
            "a delete says it is final: \(many.message)")
        expect(
            many.confirmTitle == "Delete" && one.confirmTitle == "Move to Trash",
            "the button says what it does")
    }

    static func removal() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "cleanup-removal-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let bin = root.appending(path: "bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["one", "two", "three"] {
            try fm.createDirectory(
                at: root.appending(path: "\(name)/node_modules/dep"), withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: root.appending(path: "elsewhere"), withIntermediateDirectories: true)
        try fm.removeItem(at: root.appending(path: "three/node_modules"))
        try fm.createSymbolicLink(
            at: root.appending(path: "three/node_modules"),
            withDestinationURL: root.appending(path: "elsewhere"))

        func target(_ name: String, _ folder: String = "node_modules") -> CleanupRemovalTarget {
            CleanupRemovalTarget(projectPath: root.appending(path: name).path, name: folder)
        }
        let binned = Mutex<[String]>([])
        let outcome = CleanupRunner.remove(
            [target("one"), target("three"), target("missing"), target("one", "src")], mode: .trash
        ) { url in
            binned.withLock { $0.append(url.path) }
            try FileManager.default.moveItem(at: url, to: bin.appending(path: UUID().uuidString))
        }
        expect(outcome.removed == [target("one")], "only the real build folder is trashed")
        expect(binned.withLock { $0.count } == 1, "the trash is asked once")
        expect(!fm.fileExists(atPath: target("one").path), "and the folder leaves its project")
        expect(
            outcome.failures.map(\.target) == [target("three"), target("missing"), target("one", "src")],
            "a symlink, a missing folder and a source folder each fail with a reason")
        expect(fm.fileExists(atPath: root.appending(path: "elsewhere").path), "a symlink's target stays")

        let deleted = CleanupRunner.remove([target("two")], mode: .delete) { _ in
            fatalError("delete mode must not use the trash")
        }
        expect(deleted.removed == [target("two")], "delete removes the folder")
        expect(!fm.fileExists(atPath: target("two").path), "without the trash")
    }
}
