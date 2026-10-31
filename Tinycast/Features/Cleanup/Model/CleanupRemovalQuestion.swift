import Foundation

/// The words of the confirmation a removal asks before it starts.
struct CleanupRemovalQuestion: Equatable, Sendable {
    var projects: [CleanupProject]
    var folders: Int
    var bytes: Int64
    var mode: CleanupRemovalMode

    var title: String {
        let what = projects.count == 1 ? "build folders" : "build folders of \(projects.count) projects"
        return mode == .trash ? "Move \(what) to the Trash?" : "Delete \(what)?"
    }

    var message: String {
        let size = bytes.formatted(.byteCount(style: .file))
        let scope =
            projects.count == 1
            ? projects[0].artifacts.map(\.name).joined(separator: ", ") + ", \(size)."
            : "\(folders) folders, \(size)."
        let after =
            mode == .trash
            ? "The disk gets the space back when you empty the Trash."
            : "This can't be undone."
        return "\(scope) Each project can rebuild its folders. \(after)"
    }

    var confirmTitle: String {
        mode == .trash ? "Move to Trash" : "Delete"
    }
}
