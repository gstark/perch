import AppKit

/// A plain titled window, so a panel's grouped `Form` reads like a Settings pane.
@MainActor
final class FormWindowChrome: WindowChrome {
    func install(in window: NSWindow) {
        window.titleVisibility = .visible
        // Transparent opts the titlebar out of the system's glass band; a `Form` wants it drawn.
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
    }
}
