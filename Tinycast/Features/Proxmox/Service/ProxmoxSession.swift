import Foundation

/// One open panel's view of the host; it polls only while the panel's view is on screen.
@MainActor
@Observable
final class ProxmoxSession {
    enum Phase: Equatable {
        case loading
        case loaded(ProxmoxSnapshot)
        case failed(ProxmoxFailure)
    }

    /// Proxmox's own stats daemon updates about every ten seconds, so faster polling gains nothing.
    private static let refreshInterval: Duration = .seconds(5)

    private(set) var phase: Phase = .loading
    /// Read on every refresh, so a settings change applies without reopening the panel.
    @ObservationIgnored private let connection: @MainActor () throws(ProxmoxFailure)
        -> ProxmoxConnection

    init(connection: @escaping @MainActor () throws(ProxmoxFailure) -> ProxmoxConnection) {
        self.connection = connection
    }

    /// Returns when its task is cancelled, which `.task` does as the panel closes.
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    private func refresh() async {
        do {
            let snapshot = try await ProxmoxService.snapshot(of: connection())
            guard !Task.isCancelled else { return }
            phase = .loaded(snapshot)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error)
        }
    }
}
