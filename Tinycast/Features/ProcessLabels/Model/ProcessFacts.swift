import Foundation

/// What the kernel tells us about one process, before anything is redacted.
struct ProcessFacts: Equatable, Sendable {
    let executable: String
    /// The full argv, including argv[0].
    let arguments: [String]
    let workingDirectory: String?
    let parent: String?
}
