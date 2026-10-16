import AppKit

/// Perch's one menu-bar item: the CPU meter, with Git Watch's badge to its left when it has news.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private unowned let core: AppCore
    private let sampler: CPUSampler
    private var statusItem: NSStatusItem?
    private var meter: NSImage?
    private var gitWatchBadge: NSImage?
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
        meter = MeterImage.make(loads: loads, efficiencyCount: CPUSampler.efficiencyCoreCount)
        drawImage()
        let total: Double = loads.reduce(0) { $0 + $1.user + $1.system }
        let percent = loads.isEmpty ? 0 : Int((total / Double(loads.count) * 100).rounded())
        button.setAccessibilityValue("\(percent) percent")
    }

    /// The badge sits left of the meter, so the meter keeps its place as the item widens.
    func applyGitWatch() {
        let coordinator = core.gitWatchCoordinator
        gitWatchBadge = GitWatchBadge.make(
            count: coordinator.atRiskCount, isScanning: coordinator.isScanning)
        drawImage()
    }

    private func drawImage() {
        guard let button = statusItem?.button, let meter else { return }
        button.image = gitWatchBadge.map { Self.joined($0, meter) } ?? meter
    }

    private static let badgeGap: CGFloat = 6

    private static func joined(_ badge: NSImage, _ meter: NSImage) -> NSImage {
        let size = NSSize(
            width: badge.size.width + badgeGap + meter.size.width,
            height: max(badge.size.height, meter.size.height))
        let image = NSImage(size: size, flipped: false) { _ in
            let badgeY = (size.height - badge.size.height) / 2
            badge.draw(in: NSRect(origin: NSPoint(x: 0, y: badgeY), size: badge.size))
            let meterOrigin = NSPoint(
                x: size.width - meter.size.width, y: (size.height - meter.size.height) / 2)
            meter.draw(in: NSRect(origin: meterOrigin, size: meter.size))
            return true
        }
        image.isTemplate = false
        return image
    }

    func applyVisibility() {
        statusItem?.isVisible = core.settings.showInMenuBar
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let gitWatch = core.gitWatchCoordinator
        menu.addItem(item(gitWatch.menuTitle) { $0.gitWatchCoordinator.showPanel() })
        menu.addItem(.separator())
        addProcessItems(to: menu)
        menu.addItem(item("Open Activity Monitor") { _ in ProcessControl.openActivityMonitor() })
        if core.proxmoxCoordinator.hasAddress {
            menu.addItem(item("Proxmox…") { $0.proxmoxCoordinator.showPanel() })
        }
        menu.addItem(.separator())
        addDiskItems(to: menu)
        menu.addItem(.separator())
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

    private func addDiskItems(to menu: NSMenu) {
        let disk = core.diskHistoryCoordinator
        menu.addItem(.sectionHeader(title: "Startup Disk"))
        if let current = disk.current {
            menu.addItem(DiskMenuSummary.menuItem(current: current, samples: disk.store.samples))
        }
        menu.addItem(item("Disk History…") { $0.diskHistoryCoordinator.showPanel() })
    }

    /// Each row quits its process; holding Option turns every row into Force Quit.
    private func addProcessItems(to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: "Top Processes"))
        let processes = sampler.topProcesses
        guard !processes.isEmpty else {
            let measuring = NSMenuItem(title: "Measuring…", action: nil, keyEquivalent: "")
            measuring.isEnabled = false
            menu.addItem(measuring)
            return
        }
        for usage in processes {
            let name = ProcessControl.name(of: usage.pid)
            let owned = ProcessControl.isOwnedByUser(usage.pid)
            let quit = processItem(name: name, usage: usage, owned: owned, force: false)
            quit.toolTip = owned ? "Quit \(name)" : "Owned by another user"
            menu.addItem(quit)
            menu.addItem(processItem(name: name, usage: usage, owned: owned, force: true))
        }
    }

    private func processItem(
        name: String, usage: ProcessUsage, owned: Bool, force: Bool
    ) -> NSMenuItem {
        let label = force ? "Force Quit \(name)" : name
        let item = self.item(label) { core in
            let sent = force ? ProcessControl.forceQuit(usage.pid) : ProcessControl.quit(usage.pid)
            if !sent { core.showMessage("Could not quit \(name)", tone: .danger) }
        }
        item.attributedTitle = Self.processTitle(label, percent: usage.percent)
        // Without an action AppKit greys the row, which is the disabled look wanted here.
        if !owned { item.action = nil }
        if force {
            item.keyEquivalentModifierMask = .option
            item.isAlternate = true
        }
        return item
    }

    /// The name on the left and the share on a right-aligned tab stop, so the numbers line up.
    private static func processTitle(_ name: String, percent: Double) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: processColumnWidth)]
        let shown = name.count > maxNameLength ? String(name.prefix(maxNameLength - 1)) + "…" : name
        return NSAttributedString(
            string: "\(shown)\t\(Int(percent.rounded()))%",
            attributes: [.paragraphStyle: style, .font: NSFont.menuFont(ofSize: 0)])
    }

    private static let processColumnWidth: CGFloat = 280
    private static let maxNameLength = 34

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
