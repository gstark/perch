import AppKit

/// Scans every machine on a schedule and on wake, and keeps the newest report for each host.
@MainActor
@Observable
final class GitWatchCoordinator {
    struct MachineStatus {
        var report: GitWatchReport?
        var scannedAt: Date?
        var failure: GitWatchFailure?

        /// A failed scan keeps the last report: work at risk stays at risk until a scan clears it.
        var isStale: Bool { failure != nil && report != nil }
    }

    private static let interval: Duration = .seconds(600)

    private(set) var statuses: [String: MachineStatus] = [:]
    private(set) var isScanning = false
    /// Environment injection and settings only — never for state this type owns.
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var schedule: Task<Void, Never>?
    @ObservationIgnored private var wakeToken: NotificationCenter.ObservationToken?
    @ObservationIgnored private lazy var statusItem = GitWatchStatusItem(coordinator: self)
    private var settings: AppSettings { core.settings }

    init(core: AppCore) {
        self.core = core
    }

    func start() {
        schedule = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scanAll()
                try? await Task.sleep(for: Self.interval)
            }
        }
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            of: NSWorkspace.shared, for: .didWake
        ) { [weak self] _ in
            Task { await self?.scanAll() }
        }
    }

    /// Each machine with repos at risk, ignored repos left out, in Settings order.
    var atRisk: [(machine: GitWatchMachine, repos: [GitWatchRepo])] {
        settings.gitWatchMachines.compactMap { machine in
            let repos = (statuses[machine.host]?.report?.atRisk ?? [])
                .filter { !machine.ignoredPaths.contains($0.path) }
            return repos.isEmpty ? nil : (machine, repos)
        }
    }

    func scanAll() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let machines = settings.gitWatchMachines.filter { !$0.roots.isEmpty }
        await withTaskGroup(of: (String, Result<GitWatchReport, GitWatchFailure>).self) { group in
            for machine in machines {
                group.addTask { (machine.host, await GitWatchScanner.scan(machine)) }
            }
            for await (host, result) in group {
                record(result, for: host)
            }
        }
        let hosts = Set(settings.gitWatchMachines.map(\.host))
        statuses = statuses.filter { hosts.contains($0.key) }
        refreshStatusItem()
    }

    /// The Settings button and the menu's Scan Now: the user started it, so a HUD reports it.
    func scanNow() async {
        guard !isScanning else { return }
        await scanAll()
        let count = atRisk.reduce(0) { $0 + $1.repos.count }
        let failed = statuses.values.filter { $0.failure != nil }.count
        if failed > 0 {
            core.showMessage("\(failed) machine(s) could not be scanned", tone: .danger)
        } else if count > 0 {
            core.showMessage("\(count) repo(s) with unpushed commits", tone: .neutral)
        } else {
            core.showMessage("Everything is pushed")
        }
    }

    func refreshStatusItem() {
        statusItem.update(count: atRisk.reduce(0) { $0 + $1.repos.count })
    }

    func open(_ repo: GitWatchRepo, on machine: GitWatchMachine) {
        guard !machine.isLocal else {
            NSWorkspace.shared.open(URL(filePath: repo.path, directoryHint: .isDirectory))
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(machine.terminalCommand(for: repo.path), forType: .string)
        core.showMessage("Copied an ssh command for \(repo.name)")
    }

    func showSettings() {
        core.settingsCoordinator.showSettings(tab: .gitWatch)
    }

    // MARK: - Machines

    func updateMachine(_ host: String, _ change: (inout GitWatchMachine) -> Void) {
        guard let index = settings.gitWatchMachines.firstIndex(where: { $0.host == host }) else { return }
        change(&settings.gitWatchMachines[index])
    }

    /// False when the host is empty, unsafe, or already listed.
    @discardableResult
    func addMachine(host: String) -> Bool {
        let before = settings.gitWatchMachines
        let after = GitWatchMachine.normalize(before + [GitWatchMachine(host: host, roots: ["~/dev"])])
        guard after.count > before.count else { return false }
        settings.gitWatchMachines = after
        Task { await scanAll() }
        return true
    }

    func removeMachine(host: String) {
        guard !host.isEmpty else { return }
        settings.gitWatchMachines.removeAll { $0.host == host }
        statuses[host] = nil
    }

    func ignore(_ path: String, on host: String) {
        updateMachine(host) { $0.ignoredPaths.append(path) }
    }

    func unignore(_ path: String, on host: String) {
        updateMachine(host) { $0.ignoredPaths.removeAll { $0 == path } }
    }

    private func record(_ result: Result<GitWatchReport, GitWatchFailure>, for host: String) {
        var status = statuses[host] ?? MachineStatus()
        switch result {
        case .success(let report):
            status.report = report
            status.failure = nil
        case .failure(let failure):
            status.failure = failure
        }
        status.scannedAt = .now
        statuses[host] = status
    }
}
