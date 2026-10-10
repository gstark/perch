import AppKit

/// The menu bar warning. It exists only while a default branch holds unpushed work.
@MainActor
final class GitWatchStatusItem: NSObject, NSMenuDelegate {
    private unowned let coordinator: GitWatchCoordinator
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    init(coordinator: GitWatchCoordinator) {
        self.coordinator = coordinator
        super.init()
        menu.delegate = self
    }

    func update(count: Int) {
        guard count > 0 else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        let item = statusItem ?? makeItem()
        item.button?.title = "\(count)"
        item.button?.setAccessibilityValue("\(count) repositories with unpushed commits")
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "arrow.up.circle", accessibilityDescription: "Unpushed commits")
        item.button?.imagePosition = .imageLeading
        item.button?.setAccessibilityLabel("Git Watch")
        item.menu = menu
        statusItem = item
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (machine, repos) in coordinator.atRisk {
            let stale = coordinator.statuses[machine.host]?.isStale == true
            menu.addItem(.sectionHeader(title: machine.displayName + (stale ? " (stale)" : "")))
            for repo in repos {
                let row = item("\(repo.name)  \(repo.summary)") { $0.open(repo, on: machine) }
                row.toolTip = repo.path
                menu.addItem(row)
                let ignore = item("Ignore \(repo.name)") { $0.ignore(repo.path, on: machine.host) }
                ignore.keyEquivalentModifierMask = .option
                ignore.isAlternate = true
                menu.addItem(ignore)
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Scan Now") { coordinator in Task { await coordinator.scanNow() } })
        menu.addItem(item("Git Watch Settings…") { $0.showSettings() })
    }

    private func item(
        _ title: String, action: @escaping @MainActor (GitWatchCoordinator) -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let target = MenuAction { [unowned coordinator] in action(coordinator) }
        item.target = target
        item.representedObject = target
        return item
    }
}
