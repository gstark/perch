import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The status item is AppKit's, so this scene exists only to carry the app menu's commands.
    var body: some Scene {
        Settings { EmptyView() }
            .commands { menuBarCommands }
    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {}
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close Window") { AppCore.shared.settingsCoordinator.closeSettings() }
            .keyboardShortcut("q")
        }
    }
}
