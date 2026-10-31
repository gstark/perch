import Foundation

/// The listed projects whose largest build item one kind owns.
struct CleanupGroup: Equatable, Sendable, Identifiable {
    /// Nil only for a project with no kind, which the walk never produces.
    var kind: CleanupProjectKind?
    var projects: [CleanupProject]

    var id: String { kind?.rawValue ?? "" }
    var reclaimable: Int64 { projects.reduce(0) { $0 + $1.reclaimable } }

    /// The most space first, groups and the projects in them alike.
    static func groups(_ projects: [CleanupProject]) -> [CleanupGroup] {
        Dictionary(grouping: projects, by: \.primaryKind)
            .map { kind, members in
                CleanupGroup(
                    kind: kind,
                    projects: members.sorted { ($0.reclaimable, $1.path) > ($1.reclaimable, $0.path) })
            }
            .sorted { ($0.reclaimable, $1.id) > ($1.reclaimable, $0.id) }
    }
}
