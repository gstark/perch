import Darwin
import Foundation

/// Walks the roots for projects and sizes their build folders. It never deletes anything.
nonisolated enum CleanupScanner {
    typealias Progress = @Sendable (CleanupProgress) -> Void

    /// Folders sized at once; separate folders scale to about this many on an SSD, then flatten.
    private static let sizingWidth = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount / 2))
    private static let walkReportInterval = 200

    /// Nil when cancelled; `roots` must not overlap, which `CleanupRoots.walkable` ensures.
    static func scan(
        roots: [URL], now: Date, progress: @escaping Progress = { _ in }
    ) async -> CleanupReport? {
        var walk = Walk(progress: progress)
        for root in roots {
            // Canonical, so every path below it compares equal to its own `realpath`.
            let path = canonicalPath(root.path) ?? root.path
            walk.visit(URL(filePath: path, directoryHint: .isDirectory), isRoot: true)
        }
        guard !Task.isCancelled else { return nil }
        let sizes = await size(walk.pending, counted: walk.counted, progress: progress)
        guard !Task.isCancelled else { return nil }
        var projects = walk.projects
        for (pending, size) in zip(walk.pending, sizes) {
            projects[pending.project].artifacts[pending.artifact].bytes = size.bytes
            projects[pending.project].artifacts[pending.artifact].sharedBytes = size.shared
        }
        return CleanupReport(
            projects: CleanupProject.settled(projects), unreadable: walk.unreadable, date: now)
    }

    private struct Entry {
        var url: URL
        var name: String
        var isDirectory: Bool
        var isFile: Bool
        var modified: Date
        var allocated: Int64
        var links: Int
    }

    /// A claimed build item, sized after the walk so the walk itself stays quick.
    private struct Pending: Sendable {
        var project: Int
        var artifact: Int
        /// The folder the rule works in.
        var path: String
        var rule: CleanupArtifactRule
    }

    private struct Walk {
        let progress: Progress
        var projects: [CleanupProject] = []
        var projectIndex: [String: Int] = [:]
        var pending: [Pending] = []
        var unreadable: [String] = []
        /// Every build folder found so far; a nested project must not claim one a parent owns.
        var claimed: Set<String> = []
        var counted = CleanupProgress()

        /// The newest dated entry in the folder's tree, or nil when nothing in it dates it.
        @discardableResult
        mutating func visit(_ folder: URL, isRoot: Bool = false) -> Date? {
            guard !Task.isCancelled else { return nil }
            report()
            guard let entries = CleanupScanner.list(folder) else {
                unreadable.append(folder.path)
                return nil
            }
            let marker = CleanupArtifactRule.virtualEnvironmentMarker
            if !isRoot, entries.contains(where: { $0.isFile && $0.name == marker }) {
                addEnvironment(folder)
                return nil
            }
            claimArtifacts(in: folder, entries: entries)
            var newest: Date?
            for entry in entries where !claimed.contains(entry.url.path) {
                if CleanupWalkPolicy.dates(entry.name) { newest = later(newest, entry.modified) }
                guard entry.isDirectory, CleanupWalkPolicy.descends(into: entry.name) else { continue }
                newest = later(newest, visit(entry.url))
            }
            if entries.contains(where: { $0.isDirectory && $0.name == ".git" }) {
                let log = folder.appending(path: CleanupWalkPolicy.commitLog, directoryHint: .notDirectory)
                newest = later(newest, CleanupScanner.modified(log.path))
            }
            if let index = projectIndex[folder.path] {
                projects[index].lastModified = newest ?? .distantPast
            }
            return newest
        }

        private mutating func report() {
            counted.foldersWalked += 1
            if counted.foldersWalked % CleanupScanner.walkReportInterval == 0 { progress(counted) }
        }

        /// Records the project before its children, so a parent sits above a nested project.
        private mutating func claimArtifacts(in folder: URL, entries: [Entry]) {
            let kinds = CleanupProjectKind.kinds(
                fileNames: Set(entries.filter { !$0.isDirectory }.map(\.name)),
                directoryNames: Set(entries.filter(\.isDirectory).map(\.name)))
            guard !kinds.isEmpty else { return }
            let artifacts = CleanupProjectKind.artifacts(of: kinds).compactMap { name in
                let url = folder.appending(
                    path: CleanupArtifactRule.folder(of: name), directoryHint: .isDirectory)
                return claim(url) ? (name, url.path) : nil
            }
            guard !artifacts.isEmpty else { return }
            let index = register(
                CleanupProject(
                    path: folder.path, kinds: kinds,
                    artifacts: artifacts.map {
                        CleanupArtifact(
                            name: $0.0, rule: CleanupArtifactRule(tableName: $0.0), bytes: 0,
                            sharedBytes: 0)
                    },
                    lastModified: .distantPast))
            for (artifact, (name, path)) in artifacts.enumerated() {
                pending.append(
                    Pending(
                        project: index, artifact: artifact, path: path,
                        rule: CleanupArtifactRule(tableName: name)))
            }
        }

        /// A virtual environment belongs to the folder that holds it, whatever that folder is.
        private mutating func addEnvironment(_ folder: URL) {
            claimed.insert(folder.path)
            let parent = folder.deletingLastPathComponent().path
            let artifact = CleanupArtifact(
                name: folder.lastPathComponent, rule: .virtualEnvironment, bytes: 0, sharedBytes: 0)
            let index: Int
            if let existing = projectIndex[parent] {
                index = existing
                projects[index].artifacts.append(artifact)
                let kinds = Set(projects[index].kinds + [.pythonEnvironment])
                projects[index].kinds = CleanupProjectKind.allCases.filter(kinds.contains)
            } else {
                index = register(
                    CleanupProject(
                        path: parent, kinds: [.pythonEnvironment], artifacts: [artifact],
                        lastModified: .distantPast))
            }
            pending.append(
                Pending(
                    project: index, artifact: projects[index].artifacts.count - 1,
                    path: folder.path, rule: .virtualEnvironment))
        }

        private mutating func register(_ project: CleanupProject) -> Int {
            let index = projects.count
            projects.append(project)
            projectIndex[project.path] = index
            counted.projectsFound = projects.count
            return index
        }

        private mutating func claim(_ url: URL) -> Bool {
            let path = url.path
            guard !claimed.contains(path), CleanupScanner.isRealFolder(url) else { return false }
            claimed.insert(path)
            return true
        }

        private func later(_ lhs: Date?, _ rhs: Date?) -> Date? {
            guard let lhs else { return rhs }
            guard let rhs else { return lhs }
            return max(lhs, rhs)
        }
    }

    /// `readdir` and `fstatat` walk twice as fast as `contentsOfDirectory` with resource values.
    private static func list(_ folder: URL) -> [Entry]? {
        guard let stream = opendir(folder.path) else { return nil }
        defer { closedir(stream) }
        let descriptor = dirfd(stream)
        var entries: [Entry] = []
        while let record = readdir(stream) {
            let length = Int(record.pointee.d_namlen)
            let name = withUnsafeBytes(of: record.pointee.d_name) { bytes in
                FileManager.default.string(
                    withFileSystemRepresentation: bytes.baseAddress!.assumingMemoryBound(to: CChar.self),
                    length: length)
            }
            var info = stat()
            guard name != ".", name != "..",
                fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0
            else { continue }
            let type = info.st_mode & S_IFMT
            guard type != S_IFLNK else { continue }
            let isDirectory = type == S_IFDIR
            entries.append(
                Entry(
                    url: folder.appending(
                        path: name, directoryHint: isDirectory ? .isDirectory : .notDirectory),
                    name: name, isDirectory: isDirectory, isFile: type == S_IFREG,
                    modified: date(info.st_mtimespec), allocated: Int64(info.st_blocks) * 512,
                    links: Int(info.st_nlink)))
        }
        return entries
    }

    private static func modified(_ path: String) -> Date? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return date(info.st_mtimespec)
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    /// A symlink anywhere in the path, such as `ios` in `ios/Pods`, leads to space not ours.
    static func isRealFolder(_ url: URL) -> Bool {
        guard canonicalPath(url.path) == url.path else { return false }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// `realpath`: `resolvingSymlinksInPath` and `standardizedFileURL` strip `/private` instead.
    static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Sizes in the order given, a few folders at a time.
    private static func size(
        _ items: [Pending], counted: CleanupProgress, progress: Progress
    ) async -> [(bytes: Int64, shared: Int64)] {
        var sizes = Array(repeating: (bytes: Int64(0), shared: Int64(0)), count: items.count)
        var counted = counted
        counted.foldersToSize = items.count
        progress(counted)
        await withTaskGroup(of: (Int, (bytes: Int64, shared: Int64)).self) { group in
            var next = 0
            func start() {
                guard next < items.count else { return }
                let index = next
                next += 1
                group.addTask { (index, measure(items[index])) }
            }
            for _ in 0..<sizingWidth { start() }
            for await (index, size) in group {
                sizes[index] = size
                counted.foldersSized += 1
                progress(counted)
                if !Task.isCancelled { start() }
            }
        }
        return sizes
    }

    private static func measure(_ item: Pending) -> (bytes: Int64, shared: Int64) {
        switch item.rule {
        case .folder, .virtualEnvironment:
            return allocated(in: item.path)
        case .files(let suffix):
            let files = (list(URL(filePath: item.path, directoryHint: .isDirectory)) ?? [])
                .filter { $0.isFile && $0.name.hasSuffix(suffix) }
            return (
                files.reduce(0) { $0 + $1.allocated },
                files.filter { $0.links > 1 }.reduce(0) { $0 + $1.allocated }
            )
        }
    }

    /// `fts` with `lstat` is about twice as fast as `FileManager`'s enumerator on a large tree.
    private static func allocated(in path: String) -> (bytes: Int64, shared: Int64) {
        var bytes: Int64 = 0
        var shared: Int64 = 0
        path.withCString { root in
            var roots: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(mutating: root), nil]
            guard let stream = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
                return
            }
            defer { fts_close(stream) }
            while let entry = fts_read(stream), !Task.isCancelled {
                guard Int32(entry.pointee.fts_info) == FTS_F, let stat = entry.pointee.fts_statp
                else { continue }
                let size = Int64(stat.pointee.st_blocks) * 512
                bytes += size
                if stat.pointee.st_nlink > 1 { shared += size }
            }
        }
        return (bytes, shared)
    }
}
