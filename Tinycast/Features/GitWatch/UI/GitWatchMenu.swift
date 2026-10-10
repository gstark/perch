import AppKit

/// Git Watch's row in the CPU menu; its submenu lists the repos so the process list stays in reach.
@MainActor
enum GitWatchMenu {
    /// Adds nothing while the badge is hidden, so the CPU menu only grows when there is news.
    static func addItem(to menu: NSMenu, coordinator: GitWatchCoordinator) {
        let count = coordinator.atRiskCount
        guard count > 0 || coordinator.isScanning else { return }
        let title = coordinator.isScanning ? "Git Watch: Scanning…" : "Git Watch: \(count) Unpushed"
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        root.submenu = submenu(coordinator: coordinator)
        menu.addItem(root)
        menu.addItem(.separator())
    }

    private static func submenu(coordinator: GitWatchCoordinator) -> NSMenu {
        let menu = NSMenu()
        for (machine, repos) in coordinator.atRisk {
            let stale = coordinator.statuses[machine.host]?.isStale == true
            menu.addItem(.sectionHeader(title: machine.displayName + (stale ? " (stale)" : "")))
            for repo in repos {
                let row = NSMenuItem(
                    title: "\(repo.name)  \(repo.summary)", action: nil, keyEquivalent: "")
                row.toolTip = repo.path
                row.submenu = actions(for: repo, on: machine, coordinator: coordinator)
                menu.addItem(row)
            }
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        let scanNow = item("Scan Now", coordinator) { coordinator in
            Task { await coordinator.scanNow() }
        }
        if coordinator.isScanning { scanNow.action = nil }
        menu.addItem(scanNow)
        menu.addItem(item("Git Watch Settings…", coordinator) { $0.showSettings() })
        return menu
    }

    private static func actions(
        for repo: GitWatchRepo, on machine: GitWatchMachine, coordinator: GitWatchCoordinator
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            machine.isLocal
                ? item("Open in Finder", coordinator) { $0.openInFinder(repo) }
                : item("Copy ssh Command", coordinator) { $0.copySSHCommand(repo, on: machine) })
        menu.addItem(item("Push to Remote", coordinator) { coordinator in
            Task { await coordinator.push(repo, on: machine) }
        })
        menu.addItem(.separator())
        menu.addItem(item("Ignore This Repository", coordinator) {
            $0.ignore(repo.path, on: machine.host)
        })
        return menu
    }

    private static func item(
        _ title: String, _ coordinator: GitWatchCoordinator,
        action: @escaping @MainActor (GitWatchCoordinator) -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let target = MenuAction { [unowned coordinator] in action(coordinator) }
        item.target = target
        item.representedObject = target
        return item
    }
}
