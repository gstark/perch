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
        let url = URL(filePath: target.path, directoryHint: .isDirectory)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard let values else { return "The folder is gone." }
        // A folder replaced by a symlink since the scan would take its target with it.
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            return "No longer a folder."
        }
        do {
            switch mode {
            case .trash: try trash(url)
            case .delete: try FileManager.default.removeItem(at: url)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
