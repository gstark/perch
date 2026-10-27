import AppKit
import os

/// Labels a busy process that is not an app, asking the AI once per signature and caching it.
@MainActor
@Observable
final class ProcessLabelCoordinator {
    /// Long enough that a compile step or a one-off script never costs a request.
    private static let dwell: Duration = .seconds(5)
    private static let pauseAfterFailure: Duration = .seconds(300)
    private static let tokenAccount = "api-token"
    private static let logger = Logger(subsystem: "com.gstark.perch", category: "ProcessLabels")

    let store = ProcessLabelStore(
        fileURL: AppPaths.caches()
            .appending(path: "process-labels.json", directoryHint: .notDirectory))
    /// Shown in Settings; cleared by the next success or a change to the connection.
    private(set) var lastFailure: String?
    /// Environment injection and settings only — never for state this type owns.
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var tracked: [pid_t: Tracked] = [:]
    @ObservationIgnored private var pausedUntil: ContinuousClock.Instant?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var requesting: Task<Void, Never>?

    private enum Tracked {
        case waiting(since: ContinuousClock.Instant)
        case reading
        /// An app, which already has a clear name, or a process Perch may not read.
        case skipped
        case signed(ProcessSignature)
    }

    init(core: AppCore) {
        self.core = core
    }

    var isConfigured: Bool { endpoint != nil && !model.isEmpty }

    private var endpoint: URL? {
        ProcessLabelFormat.endpoint(from: core.settings.processLabelEndpoint)
    }

    private var model: String {
        core.settings.processLabelModel.trimmingCharacters(in: .whitespaces)
    }

    func start() {
        loading = Task { [weak self] in await self?.store.load() }
    }

    func stop() {
        loading?.cancel()
        requesting?.cancel()
    }

    func label(for pid: pid_t) -> String? {
        guard case .signed(let signature) = tracked[pid] else { return nil }
        return store.label(for: signature)
    }

    /// Called once per sample; a pid that leaves the list starts its dwell again if it returns.
    func observe(_ top: [ProcessUsage]) {
        guard isConfigured else {
            tracked = [:]
            return
        }
        let now = ContinuousClock.now
        let pids = Set(top.map(\.pid))
        tracked = tracked.filter { pids.contains($0.key) }
        for pid in pids {
            switch tracked[pid] {
            case nil: tracked[pid] = .waiting(since: now)
            case .waiting(let since) where now - since >= Self.dwell: read(pid)
            default: break
            }
        }
        requestNext(now: now)
    }

    private func read(_ pid: pid_t) {
        guard NSRunningApplication(processIdentifier: pid)?.bundleURL == nil else {
            tracked[pid] = .skipped
            return
        }
        tracked[pid] = .reading
        let home = NSHomeDirectory()
        Task { [weak self] in
            let facts = await Task.detached(priority: .utility) {
                ProcessFactsReader.read(pid: pid)
            }.value
            guard let self, case .reading = tracked[pid] else { return }
            guard let facts else {
                tracked[pid] = .skipped
                return
            }
            tracked[pid] = .signed(ProcessSignature(facts: facts, home: home))
        }
    }

    /// One request at a time; each sample picks the next signature still missing a label.
    private func requestNext(now: ContinuousClock.Instant) {
        let isPaused = pausedUntil.map { now < $0 } ?? false
        guard requesting == nil, !isPaused, let endpoint else { return }
        let signature = tracked.values.lazy.compactMap { entry -> ProcessSignature? in
            guard case .signed(let signature) = entry, self.store.label(for: signature) == nil
            else { return nil }
            return signature
        }.first
        guard let signature else { return }
        let model = model
        let token = storedToken()
        requesting = Task { [weak self] in
            do throws(ProcessLabelFailure) {
                let label = try await ProcessLabelService.label(
                    for: signature, endpoint: endpoint, model: model, token: token)
                await self?.record(label, for: signature)
            } catch {
                self?.fail(error)
            }
            self?.requesting = nil
        }
    }

    private func record(_ label: String, for signature: ProcessSignature) async {
        lastFailure = nil
        if await !store.record(label, for: signature, at: .now) {
            Self.logger.error("Couldn't save the process label cache")
        }
    }

    private func fail(_ failure: ProcessLabelFailure) {
        lastFailure = failure.message
        pausedUntil = .now + Self.pauseAfterFailure
    }

    /// A changed connection deserves an immediate retry rather than waiting out the pause.
    func connectionChanged() {
        lastFailure = nil
        pausedUntil = nil
    }

    /// Empty when no endpoint is set; a service without `/models` throws.
    func availableModels() async throws(ProcessLabelFailure) -> [String] {
        guard let url = ProcessLabelFormat.modelsEndpoint(from: core.settings.processLabelEndpoint)
        else { return [] }
        return try await ProcessLabelService.models(endpoint: url, token: storedToken())
    }

    /// Bypasses the pause and the cache, so Settings can prove the connection at once.
    func testAnswer(to question: String) async throws(ProcessLabelFailure) -> String {
        guard let endpoint, !model.isEmpty else { return "" }
        let answer = try await ProcessLabelService.answer(
            to: question, endpoint: endpoint, model: model, token: storedToken())
        connectionChanged()
        return answer
    }

    func clearLabels() async {
        if await !store.removeAll() {
            core.showMessage("Couldn't clear the process labels", tone: .danger)
        }
    }

    // MARK: - Token

    var hasToken: Bool {
        (try? KeychainSecretStore.processLabels.hasSecret(for: Self.tokenAccount)) ?? false
    }

    @discardableResult
    func saveToken(_ token: String) -> Bool {
        do {
            try KeychainSecretStore.processLabels.setSecret(token, for: Self.tokenAccount)
            connectionChanged()
            return true
        } catch {
            core.showMessage("Couldn't save the token to the Keychain", tone: .danger)
            return false
        }
    }

    func removeToken() {
        do {
            try KeychainSecretStore.processLabels.removeSecret(for: Self.tokenAccount)
            connectionChanged()
        } catch {
            core.showMessage("Couldn't remove the token from the Keychain", tone: .danger)
        }
    }

    private func storedToken() -> String? {
        try? KeychainSecretStore.processLabels.secret(for: Self.tokenAccount)
    }
}
