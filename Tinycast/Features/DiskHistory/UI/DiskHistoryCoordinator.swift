import AppKit

/// Reads the startup disk every few minutes, and records one sample per clock hour.
@MainActor
@Observable
final class DiskHistoryCoordinator {
    private static let checkInterval: Duration = .seconds(300)

    let store: DiskHistoryStore
    /// The newest reading, recorded or not, so the menu never lags the disk by up to an hour.
    private(set) var current: DiskSample?
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private let window: AppWindowController
    /// Environment injection and HUD messages only — never for state this type owns.
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var schedule: Task<Void, Never>?
    @ObservationIgnored private var wakeToken: NotificationCenter.ObservationToken?

    init(core: AppCore) {
        self.core = core
        store = DiskHistoryStore(
            fileURL: AppPaths.applicationSupport()
                .appending(path: "disk-history.csv", directoryHint: .notDirectory))
        window = AppWindowController(
            title: "Disk History", contentSize: Theme.Size.diskHistoryWindow,
            minimumSize: Theme.Size.diskHistoryWindowMinimum, resizable: true,
            autosaveName: "DiskHistoryWindow", activation: core.activationPolicy,
            closesOnEscape: true)
    }

    func start() {
        schedule = Task { [weak self] in
            await self?.store.load()
            self?.observeWake()
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    func showPanel() {
        window.show(chrome: FormWindowChrome()) {
            DiskHistoryPanelView().environment(core)
        }
    }

    func revealFile() {
        AppLauncher.showInFinder(store.fileURL)
    }

    private func observeWake() {
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            of: NSWorkspace.shared, for: .didWake
        ) { [weak self] _ in
            Task { await self?.check() }
        }
    }

    private func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let now = Date.now
        guard let sample = await Task.detached(operation: { DiskSpaceReader.read(at: now) }).value
        else { return }
        current = sample
        guard DiskHistory.isDue(last: store.samples.last?.date, now: now) else { return }
        if await !store.append(sample) {
            core.showMessage("Couldn't save disk history", tone: .danger)
        }
    }
}
