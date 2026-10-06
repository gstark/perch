import AppKit

/// Perch's one menu-bar item. Either click opens the same menu, rebuilt each time it opens.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private unowned let core: AppCore
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    init(core: AppCore) {
        self.core = core
        super.init()
        menu.delegate = self
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(named: "MenuBarIcon")
        item.button?.setAccessibilityLabel(Bundle.main.appDisplayName)
        item.menu = menu
        statusItem = item
        applyVisibility()
    }

    func applyVisibility() {
        statusItem?.isVisible = core.settings.showInMenuBar
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Open Launcher") { $0.paletteCoordinator.showPalette(mode: .launcher) })
        if core.settings.clipboardEnabled {
            menu.addItem(
                item("Clipboard History") { $0.paletteCoordinator.showPalette(mode: .clipboard) })
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…") { $0.settingsCoordinator.showSettings() })
        menu.addItem(.separator())
        menu.addItem(item("Quit \(Bundle.main.appDisplayName)") { _ in NSApp.terminate(nil) })
    }

    private func item(_ title: String, action: @escaping @MainActor (AppCore) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let target = MenuAction { [unowned core] in action(core) }
        item.target = target
        item.representedObject = target
        return item
    }
}

/// An `NSMenuItem` target holding its closure; the item keeps it alive through `representedObject`.
@MainActor
final class MenuAction: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func run() { action() }
}
