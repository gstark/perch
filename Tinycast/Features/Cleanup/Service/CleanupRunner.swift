import Foundation

/// Moves build folders to the Trash or deletes them. The coordinator asks first; this never does.
nonisolated enum CleanupRunner {
    typealias Trash = @Sendable (URL) throws -> Void

    /// `trash` is a parameter so the harness never fills the user's real Trash.
    static func remove(
        _ targets: [CleanupRemovalTarget], mode: CleanupRemovalMode,
        trash: Trash = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) -> CleanupRemovalOutcome {
        var outcome = CleanupRemovalOutcome()
        for target in targets {
            guard !Task.isCancelled else { break }
            if let message = remove(target, mode: mode, trash: trash) {
                outcome.failures.append(CleanupRemovalFailure(target: target, message: message))
            } else {
                outcome.removed.append(target)
            }
        }
        return outcome
    }

    /// Nil on success, otherwise why the folder stayed.
    private static func remove(
        _ target: CleanupRemovalTarget, mode: CleanupRemovalMode, trash: Trash
    ) -> String? {
        guard CleanupRemovalPolicy.isSafe(target) else { return "Not a build folder." }
        let folder = URL(filePath: target.folderPath, directoryHint: .isDirectory)
        // A path that gained a symlink since the scan would take the symlink's target with it.
        guard CleanupScanner.isRealFolder(folder) else {
            return "The folder is gone, or a symlink now leads to it."
        }
        do {
            switch target.rule {
            case .folder:
                try remove(folder, mode: mode, trash: trash)
            case .virtualEnvironment:
                let marker = folder.appending(path: CleanupArtifactRule.virtualEnvironmentMarker)
                guard FileManager.default.fileExists(atPath: marker.path) else {
                    return "No longer a Python environment."
                }
                try remove(folder, mode: mode, trash: trash)
            case .files(let suffix):
                for file in try files(in: folder, suffix: suffix) {
                    try remove(file, mode: mode, trash: trash)
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func remove(_ url: URL, mode: CleanupRemovalMode, trash: Trash) throws {
        switch mode {
        case .trash: try trash(url)
        case .delete: try FileManager.default.removeItem(at: url)
        }
    }

    /// Regular files only, read now rather than at scan time, so a new log file goes too.
    private static func files(in folder: URL, suffix: String) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        return try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))
            .filter { url in
                let values = try? url.resourceValues(forKeys: keys)
                return url.lastPathComponent.hasSuffix(suffix) && values?.isRegularFile == true
                    && values?.isSymbolicLink != true
            }
    }
}
