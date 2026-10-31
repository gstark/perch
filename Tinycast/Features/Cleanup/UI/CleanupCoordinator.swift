import AppKit

/// Finds build folders under the chosen roots on request, and removes them once confirmed.
@MainActor
@Observable
final class CleanupCoordinator {
    private(set) var report: CleanupReport?
    private(set) var isScanning = false
    private(set) var isRemoving = false
    /// Nil until the scan reports, and again once it ends.
    private(set) var progress: CleanupProgress?
    /// Kept while the app runs, so reopening the window shows the same list.
    var age: CleanupAge = .threeMonths
    @ObservationIgnored private var scan: Task<Void, Never>?
    @ObservationIgnored private let window: AppWindowController
    /// Environment injection and settings only — never for state this type owns.
    @ObservationIgnored private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: "Clean Up Projects", contentSize: Theme.Size.cleanupWindow,
            minimumSize: Theme.Size.cleanupWindowMinimum, resizable: true,
            autosaveName: "CleanupWindow", activation: core.activationPolicy, closesOnEscape: true)
    }

    var roots: [String] { core.settings.cleanupRoots }

    func showPanel() {
        window.show(chrome: FormWindowChrome()) {
            CleanupPanelView().environment(core)
        }
    }

    func startScan() {
        let roots = CleanupRoots.walkable(core.settings.cleanupRoots, home: NSHomeDirectory())
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
        guard !roots.isEmpty else { return }
        scan?.cancel()
        isScanning = true
        progress = nil
        scan = Task { [weak self] in
            // Only the newest report matters, so a slow window never queues a backlog.
            let (updates, sink) = AsyncStream.makeStream(
                of: CleanupProgress.self, bufferingPolicy: .bufferingNewest(1))
            let walk = Task.detached {
                defer { sink.finish() }
                return await CleanupScanner.scan(roots: roots, now: .now) { sink.yield($0) }
            }
            let report = await withTaskCancellationHandler {
                for await update in updates { self?.progress = update }
                return await walk.value
            } onCancel: {
                walk.cancel()
            }
            guard let self, !Task.isCancelled else { return }
            isScanning = false
            progress = nil
            if let report { self.report = report }
        }
    }

    func cancelScan() {
        scan?.cancel()
        scan = nil
        isScanning = false
        progress = nil
    }

    /// Every route to removal lands here, so none can skip the confirmation.
    func remove(_ projects: [CleanupProject], mode: CleanupRemovalMode) async {
        guard !isRemoving, !isScanning, let report else { return }
        let targets = CleanupRemovalPolicy.targets(for: projects)
        guard !targets.isEmpty else { return }
        let bytes = CleanupRemovalPolicy.reclaimable(of: targets, in: report)
        let question = CleanupRemovalQuestion(
            projects: projects, folders: targets.count, bytes: bytes, mode: mode)
        guard
            await core.confirm(
                title: question.title, message: question.message,
                symbol: mode == .trash ? "trash" : "xmark.bin", confirmTitle: question.confirmTitle),
            !isRemoving, !isScanning
        else { return }
        isRemoving = true
        core.showProgress(mode == .trash ? "Moving to the Trash…" : "Deleting…")
        let outcome = await Task.detached { CleanupRunner.remove(targets, mode: mode) }.value
        core.hideProgress()
        isRemoving = false
        if let current = self.report {
            self.report = CleanupRemovalPolicy.report(current, without: outcome.removed)
        }
        await announce(outcome, mode: mode, in: report)
    }

    private func announce(
        _ outcome: CleanupRemovalOutcome, mode: CleanupRemovalMode, in report: CleanupReport
    ) async {
        if !outcome.removed.isEmpty {
            let bytes = DiskBytes.text(CleanupRemovalPolicy.reclaimable(of: outcome.removed, in: report))
            let folders = outcome.removed.count == 1 ? "1 folder" : "\(outcome.removed.count) folders"
            core.showMessage(
                mode == .trash
                    ? "Moved \(folders) to the Trash, \(bytes)" : "Deleted \(folders), \(bytes)")
        }
        guard !outcome.failures.isEmpty else { return }
        let lines = outcome.failures.prefix(5).map {
            "\(CleanupRoots.abbreviate($0.target.path, home: NSHomeDirectory())): \($0.message)"
        }
        let more = outcome.failures.count > 5 ? "\nand \(outcome.failures.count - 5) more" : ""
        _ = await core.reportFailure(
            title: "Couldn't remove \(outcome.failures.count) folders",
            message: lines.joined(separator: "\n") + more, symbol: "exclamationmark.triangle",
            recovery: nil)
    }

    func addRoots() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders that hold your projects."
        // Perch is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        core.settings.cleanupRoots = CleanupRoots.normalize(
            core.settings.cleanupRoots + panel.urls.map(\.path), home: NSHomeDirectory())
    }

    func removeRoot(_ root: String) {
        core.settings.cleanupRoots.removeAll { $0 == root }
    }

    func reveal(_ project: CleanupProject) {
        AppLauncher.showInFinder(URL(filePath: project.path, directoryHint: .isDirectory))
    }
}
