import Foundation

/// How a build item is found, sized and removed.
enum CleanupArtifactRule: Hashable, Sendable {
    /// The folder itself, named by the project kind's table.
    case folder
    /// Files with this suffix directly in the folder, which stays: Rails tracks `log/.keep`.
    case files(suffix: String)
    /// A folder that holds `pyvenv.cfg`, whatever its name.
    case virtualEnvironment

    static let virtualEnvironmentMarker = "pyvenv.cfg"
    private static let wildcard = "/*"

    /// The table spells a file rule as `log/*.log`; every other name is a folder.
    init(tableName name: String) {
        guard let range = name.range(of: Self.wildcard) else {
            self = .folder
            return
        }
        self = .files(suffix: String(name[range.upperBound...]))
    }

    /// The folder the rule works in, relative to the project.
    static func folder(of name: String) -> String {
        name.range(of: wildcard).map { String(name[..<$0.lowerBound]) } ?? name
    }
}
