import Foundation

enum CleanupRemovalMode: Sendable {
    case trash, delete
}

/// One build folder to remove, named by the project that owns it.
struct CleanupRemovalTarget: Hashable, Sendable {
    var projectPath: String
    var name: String
    var rule: CleanupArtifactRule

    init(projectPath: String, name: String, rule: CleanupArtifactRule = .folder) {
        self.projectPath = projectPath
        self.name = name
        self.rule = rule
    }

    init(_ project: CleanupProject, _ artifact: CleanupArtifact) {
        self.init(projectPath: project.path, name: artifact.name, rule: artifact.rule)
    }

    /// As the row shows it, `log/*.log` included.
    var path: String { projectPath + "/" + name }

    /// The folder the rule works in: the build folder itself, or the folder its files sit in.
    var folderPath: String { projectPath + "/" + CleanupArtifactRule.folder(of: name) }
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

    /// A table name or an environment folder, under an absolute project path that cannot climb out.
    static func isSafe(_ target: CleanupRemovalTarget) -> Bool {
        let project = target.projectPath.split(separator: "/", omittingEmptySubsequences: false)
        guard target.projectPath.hasPrefix("/"), project.count > 1,
            !project.dropFirst().contains(where: isUnsafeStep)
        else { return false }
        switch target.rule {
        case .folder, .files:
            return knownNames.contains(target.name) && target.rule == .init(tableName: target.name)
        case .virtualEnvironment:
            return !target.name.contains("/") && !isUnsafeStep(Substring(target.name))
        }
    }

    private static func isUnsafeStep(_ step: Substring) -> Bool {
        step.isEmpty || step == "." || step == ".."
    }

    static func targets(for projects: [CleanupProject]) -> [CleanupRemovalTarget] {
        projects.flatMap { project in project.artifacts.map { CleanupRemovalTarget(project, $0) } }
    }

    static func reclaimable(of targets: [CleanupRemovalTarget], in report: CleanupReport) -> Int64 {
        let wanted = Set(targets)
        return report.projects.reduce(0) { total, project in
            total
                + project.artifacts
                .filter { wanted.contains(CleanupRemovalTarget(project, $0)) }
                .reduce(0) { $0 + $1.reclaimable }
        }
    }

    /// The report without the removed folders; a project left with none drops out.
    static func report(_ report: CleanupReport, without removed: [CleanupRemovalTarget]) -> CleanupReport {
        let gone = Set(removed)
        var report = report
        report.projects = report.projects.compactMap { project in
            var project = project
            let path = project.path
            project.artifacts.removeAll {
                gone.contains(CleanupRemovalTarget(projectPath: path, name: $0.name, rule: $0.rule))
            }
            return project.artifacts.isEmpty ? nil : project
        }
        return report
    }
}
