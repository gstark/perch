import Foundation

enum CleanupRemovalMode: Sendable {
    case trash, delete
}

/// One build folder to remove, named by the project that owns it.
struct CleanupRemovalTarget: Hashable, Sendable {
    var projectPath: String
    var name: String

    var path: String { projectPath + "/" + name }
}

/// What a removal did; a folder that failed keeps its place in the report.
struct CleanupRemovalOutcome: Equatable, Sendable {
    var removed: [CleanupRemovalTarget] = []
    var failures: [CleanupRemovalFailure] = []
}

struct CleanupRemovalFailure: Equatable, Sendable {
    var target: CleanupRemovalTarget
    var message: String
}

enum CleanupRemovalPolicy {
    private static let knownNames = Set(CleanupProjectKind.allCases.flatMap(\.artifacts))

    /// A name the table knows, under an absolute project path with no step that climbs out.
    static func isSafe(_ target: CleanupRemovalTarget) -> Bool {
        let project = target.projectPath.split(separator: "/", omittingEmptySubsequences: false)
        return target.projectPath.hasPrefix("/") && project.count > 1
            && !project.dropFirst().contains { $0.isEmpty || $0 == "." || $0 == ".." }
            && knownNames.contains(target.name)
    }

    static func targets(for projects: [CleanupProject]) -> [CleanupRemovalTarget] {
        projects.flatMap { project in
            project.artifacts.map { CleanupRemovalTarget(projectPath: project.path, name: $0.name) }
        }
    }

    static func reclaimable(of targets: [CleanupRemovalTarget], in report: CleanupReport) -> Int64 {
        let wanted = Set(targets)
        return report.projects.reduce(0) { total, project in
            total
                + project.artifacts
                .filter { wanted.contains(CleanupRemovalTarget(projectPath: project.path, name: $0.name)) }
                .reduce(0) { $0 + $1.reclaimable }
        }
    }

    /// The report without the removed folders; a project left with none drops out.
    static func report(_ report: CleanupReport, without removed: [CleanupRemovalTarget]) -> CleanupReport {
        let gone = Set(removed)
        var report = report
        report.projects = report.projects.compactMap { project in
            var project = project
            project.artifacts.removeAll {
                gone.contains(CleanupRemovalTarget(projectPath: project.path, name: $0.name))
            }
            return project.artifacts.isEmpty ? nil : project
        }
        return report
    }
}
