import AppKit

/// Perch's one menu-bar item: the CPU meter. Either click opens the same menu, rebuilt each time.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private unowned let core: AppCore
    private let sampler: CPUSampler
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    init(core: AppCore, sampler: CPUSampler) {
        self.core = core
        self.sampler = sampler
        super.init()
        menu.delegate = self
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("CPU")
        item.menu = menu
        statusItem = item
        applyVisibility()
        // Idle cells until the first interval is measured, so the item never jumps in width.
        drawMeter(Array(repeating: .idle, count: ProcessInfo.processInfo.processorCount))
        sampler.onSample = { [weak self] in
            guard let self else { return }
            drawMeter(sampler.cores)
        }
        sampler.start()
    }

    private func drawMeter(_ loads: [CoreLoad]) {
        guard let button = statusItem?.button else { return }
        button.image = MeterImage.make(loads: loads)
        let busy = loads.isEmpty ? 0 : loads.map { $0.user + $0.system }.reduce(0, +) / Double(loads.count)
        button.setAccessibilityValue("\(Int((busy * 100).rounded())) percent")
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
