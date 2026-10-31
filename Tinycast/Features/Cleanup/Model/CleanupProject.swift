import Foundation

/// One build folder and what removing it would give back.
struct CleanupArtifact: Equatable, Sendable {
    /// Relative to the project folder, as `CleanupProjectKind.artifacts` spells it.
    var name: String
    var bytes: Int64
    /// Files hard-linked elsewhere, as in a pnpm store; removing this copy frees none of it.
    var sharedBytes: Int64

    var reclaimable: Int64 { bytes - sharedBytes }
}

/// A project folder that holds at least one build folder.
struct CleanupProject: Equatable, Sendable, Identifiable {
    var path: String
    var kinds: [CleanupProjectKind]
    var artifacts: [CleanupArtifact]
    /// The newest change outside every build folder, nested projects included.
    var lastModified: Date

    var id: String { path }
    var reclaimable: Int64 { artifacts.reduce(0) { $0 + $1.reclaimable } }
}

/// One finished walk of the roots.
struct CleanupReport: Equatable, Sendable {
    var projects: [CleanupProject]
    /// Folders the walk could not list, so the totals may be short.
    var unreadable: [String]
    var date: Date
}
