import Foundation

/// The standard macOS folders the launcher opens in Finder, in the order Finder's sidebar lists them.
enum FolderCatalog {
    struct Folder: Equatable, Sendable {
        /// Stable across renames and languages, so aliases and visibility survive both.
        let id: String
        let name: String
        let url: URL
        var keywords: [String] = []
    }

    nonisolated static func folders(home: URL) -> [Folder] {
        func inHome(_ path: String) -> URL { home.appending(path: path, directoryHint: .isDirectory) }
        return [
            Folder(id: "folder:home", name: "Home", url: home, keywords: [home.lastPathComponent]),
            Folder(id: "folder:desktop", name: "Desktop", url: inHome("Desktop")),
            Folder(id: "folder:documents", name: "Documents", url: inHome("Documents")),
            Folder(id: "folder:downloads", name: "Downloads", url: inHome("Downloads")),
            Folder(id: "folder:pictures", name: "Pictures", url: inHome("Pictures"), keywords: ["Photos"]),
            Folder(id: "folder:movies", name: "Movies", url: inHome("Movies"), keywords: ["Videos"]),
            Folder(id: "folder:music", name: "Music", url: inHome("Music")),
            Folder(id: "folder:public", name: "Public", url: inHome("Public"), keywords: ["Drop Box"]),
            Folder(
                id: "folder:icloud-drive", name: "iCloud Drive",
                url: inHome("Library/Mobile Documents/com~apple~CloudDocs")),
            Folder(id: "folder:library", name: "Library", url: inHome("Library")),
            Folder(
                id: "folder:applications", name: "Applications",
                url: URL(filePath: "/Applications", directoryHint: .isDirectory)),
            Folder(
                id: "folder:utilities", name: "Utilities",
                url: URL(filePath: "/Applications/Utilities", directoryHint: .isDirectory)),
            Folder(
                id: "folder:computer", name: "Macintosh HD",
                url: URL(filePath: "/", directoryHint: .isDirectory), keywords: ["Computer", "Root"]),
            Folder(id: "folder:trash", name: "Trash", url: inHome(".Trash"), keywords: ["Bin"])
        ]
    }
}
