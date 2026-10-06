import Foundation

/// Everything in Perch a global shortcut can be bound to.
enum HotKeyAction: Hashable, Sendable {
    /// The one fixed action with no command row of its own.
    case togglePalette
    /// Parameterised over the catalog, so a new built-in command is bindable with no case here.
    case command(CommandID)
    case app(bundleID: String)
    case settingsPane(bundleID: String)
    case windowCommand(id: WindowCommand.ID)
    case customWindowSize(id: UUID)

    /// The UserDefaults key, and the `HotKeyCenter` registration id: one per action.
    var defaultsKey: String {
        switch self {
        case .togglePalette: "hotkey.togglePalette"
        case .command(let id): "hotkey." + id.rawValue
        case .app(let bundleID): "hotkey.app." + bundleID
        case .settingsPane(let bundleID): "hotkey.pane." + bundleID
        case .windowCommand(let id): "hotkey.windowCommand." + id.rawValue
        case .customWindowSize(let id):
            "hotkey.customWindowSize." + id.uuidString.lowercased()
        }
    }

    /// The fixed actions every install can bind; the per-item catalogs extend them at launch.
    static let builtInActions: [HotKeyAction] =
        [.togglePalette] + CommandID.allCases.compactMap(\.hotKeyAction)
}
