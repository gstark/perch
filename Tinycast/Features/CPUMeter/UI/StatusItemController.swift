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
            core.processLabelCoordinator.observe(sampler.topProcesses)
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
        let labels = core.processLabelCoordinator
        let rows = processes.map { usage in
            ProcessRow(
                name: ProcessControl.name(of: usage.pid), description: labels.label(for: usage.pid),
                usage: usage)
        }
        // A label can outgrow the default column, so the percentages move right to clear it.
        let widest = rows.map {
            Self.leadingText($0.name, description: $0.description).size().width
        }.max() ?? 0
        let column = max(Self.processColumnWidth, widest + Self.percentWidth)
        for row in rows {
            let owned = ProcessControl.isOwnedByUser(row.usage.pid)
            let quit = processItem(row, column: column, owned: owned, force: false)
            quit.toolTip = owned ? "Quit \(row.name)" : "Owned by another user"
            menu.addItem(quit)
            menu.addItem(processItem(row, column: column, owned: owned, force: true))
        }
    }

    private struct ProcessRow {
        let name: String
        /// What `ProcessLabelCoordinator` learned the process is doing, when it knows.
        let description: String?
        let usage: ProcessUsage
    }

    private func processItem(
        _ row: ProcessRow, column: CGFloat, owned: Bool, force: Bool
    ) -> NSMenuItem {
        let name = row.name
        let usage = row.usage
        let label = force ? "Force Quit \(name)" : name
        let item = self.item(label) { core in
            let sent = force ? ProcessControl.forceQuit(usage.pid) : ProcessControl.quit(usage.pid)
            if !sent { core.showMessage("Could not quit \(name)", tone: .danger) }
        }
        let leading = Self.leadingText(label, description: force ? nil : row.description)
        item.attributedTitle = Self.processTitle(leading, percent: usage.percent, column: column)
        // Without an action AppKit greys the row, which is the disabled look wanted here.
        if !owned { item.action = nil }
        if force {
            item.keyEquivalentModifierMask = .option
            item.isAlternate = true
        }
        return item
    }

    /// The name, then any label in the secondary colour, as "ruby (dev server in ~/dev/shop)".
    private static func leadingText(_ name: String, description: String?) -> NSAttributedString {
        let font: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        let shown = name.count > maxNameLength ? String(name.prefix(maxNameLength - 1)) + "…" : name
        let text = NSMutableAttributedString(string: shown, attributes: font)
        if let description {
            var muted = font
            muted[.foregroundColor] = NSColor.secondaryLabelColor
            text.append(NSAttributedString(string: " (\(description))", attributes: muted))
        }
        return text
    }

    /// The leading text, then the share on a right-aligned tab stop, so the numbers line up.
    private static func processTitle(
        _ leading: NSAttributedString, percent: Double, column: CGFloat
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: column)]
        let title = NSMutableAttributedString(attributedString: leading)
        title.append(
            NSAttributedString(
                string: "\t\(Int(percent.rounded()))%",
                attributes: [.font: NSFont.menuFont(ofSize: 0)]))
        title.addAttribute(
            .paragraphStyle, value: style, range: NSRange(location: 0, length: title.length))
        return title
    }

    private static let processColumnWidth: CGFloat = 280
    /// Room right of the widest label for a share such as "100%".
    private static let percentWidth: CGFloat = 56
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
