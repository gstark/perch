import Foundation

/// How far a scan has got: first the walk for projects, then the sizing of their build folders.
struct CleanupProgress: Equatable, Sendable {
    var foldersWalked = 0
    var projectsFound = 0
    var foldersSized = 0
    /// Zero until the walk ends and the build folders are known.
    var foldersToSize = 0

    var isSizing: Bool { foldersToSize > 0 }

    var text: String {
        guard isSizing else {
            return "Walked \(foldersWalked) folders, found \(projectsFound) projects"
        }
        return "Sized \(foldersSized) of \(foldersToSize) build folders"
    }
}
