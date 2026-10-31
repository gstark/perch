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
            walk.visit(root.standardizedFileURL.resolvingSymlinksInPath())
        }
        guard !Task.isCancelled else { return nil }
        let sizes = await size(walk.pending.map(\.path), counted: walk.counted, progress: progress)
        guard !Task.isCancelled else { return nil }
        var projects = walk.projects
        for (pending, size) in zip(walk.pending, sizes) {
            projects[pending.project].artifacts[pending.artifact].bytes = size.bytes
            projects[pending.project].artifacts[pending.artifact].sharedBytes = size.shared
        }
        return CleanupReport(projects: projects, unreadable: walk.unreadable, date: now)
    }

    private struct Entry {
        var url: URL
        var name: String
        var isDirectory: Bool
        var modified: Date
    }

    /// A claimed build folder, sized after the walk so the walk itself stays quick.
    private struct Pending {
        var project: Int
        var artifact: Int
        var path: String
    }

    private struct Walk {
        let progress: Progress
        var projects: [CleanupProject] = []
        var pending: [Pending] = []
        var unreadable: [String] = []
        /// Every build folder found so far; a nested project must not claim one a parent owns.
        var claimed: Set<String> = []
        var counted = CleanupProgress()

        /// The newest dated entry in the folder's tree, or nil when nothing in it dates it.
        @discardableResult
        mutating func visit(_ folder: URL) -> Date? {
            guard !Task.isCancelled else { return nil }
            report()
            guard let entries = CleanupScanner.list(folder) else {
                unreadable.append(folder.path)
                return nil
            }
            let found = claimArtifacts(in: folder, entries: entries)
            var newest: Date?
            for entry in entries where !claimed.contains(entry.url.path) {
                if CleanupWalkPolicy.dates(entry.name) { newest = later(newest, entry.modified) }
                guard entry.isDirectory, CleanupWalkPolicy.descends(into: entry.name) else { continue }
                newest = later(newest, visit(entry.url))
            }
            if let found {
                projects[found].lastModified = newest ?? .distantPast
            }
            return newest
        }

        private mutating func report() {
            counted.foldersWalked += 1
            if counted.foldersWalked % CleanupScanner.walkReportInterval == 0 { progress(counted) }
        }

        /// Records the project before its children, so a parent sits above a nested project.
        private mutating func claimArtifacts(in folder: URL, entries: [Entry]) -> Int? {
            let kinds = CleanupProjectKind.kinds(
                fileNames: Set(entries.filter { !$0.isDirectory }.map(\.name)),
                directoryNames: Set(entries.filter(\.isDirectory).map(\.name)))
            guard !kinds.isEmpty else { return nil }
            let names = CleanupProjectKind.artifacts(of: kinds).filter { name in
                claim(folder.appending(path: name, directoryHint: .isDirectory))
            }
            guard !names.isEmpty else { return nil }
            let index = projects.count
            for (artifact, name) in names.enumerated() {
                let path = folder.appending(path: name, directoryHint: .isDirectory)
                pending.append(Pending(project: index, artifact: artifact, path: path.path))
            }
            projects.append(
                CleanupProject(
                    path: folder.path, kinds: kinds,
                    artifacts: names.map { CleanupArtifact(name: $0, bytes: 0, sharedBytes: 0) },
                    lastModified: .distantPast))
            counted.projectsFound = projects.count
            return index
        }

        private mutating func claim(_ url: URL) -> Bool {
            let path = url.standardizedFileURL.path
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
            let modified = info.st_mtimespec
            entries.append(
                Entry(
                    url: folder.appending(
                        path: name, directoryHint: isDirectory ? .isDirectory : .notDirectory),
                    name: name, isDirectory: isDirectory,
                    modified: Date(
                        timeIntervalSince1970: TimeInterval(modified.tv_sec)
                            + TimeInterval(modified.tv_nsec) / 1_000_000_000)))
        }
        return entries
    }

    /// A symlinked build folder points at space this project does not own.
    private static func isRealFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    /// Sizes in the order given, a few folders at a time.
    private static func size(
        _ paths: [String], counted: CleanupProgress, progress: Progress
    ) async -> [(bytes: Int64, shared: Int64)] {
        var sizes = Array(repeating: (bytes: Int64(0), shared: Int64(0)), count: paths.count)
        var counted = counted
        counted.foldersToSize = paths.count
        progress(counted)
        await withTaskGroup(of: (Int, (bytes: Int64, shared: Int64)).self) { group in
            var next = 0
            func start() {
                guard next < paths.count else { return }
                let index = next
                next += 1
                group.addTask { (index, allocated(in: paths[index])) }
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
