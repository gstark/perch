import SwiftUI

/// The Proxmox panel, the token secret in the Keychain, and the certificate trust decision.
@MainActor
final class ProxmoxCoordinator {
    private static let secretAccount = "token-secret"

    private let window: AppWindowController
    /// Environment injection and settings only — never for state this type owns.
    private unowned let core: AppCore
    private var settings: AppSettings { core.settings }

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: "Proxmox", contentSize: Theme.Size.proxmoxWindow,
            minimumSize: Theme.Size.proxmoxWindowMinimum, resizable: true,
            autosaveName: "ProxmoxWindow", activation: core.activationPolicy, closesOnEscape: true)
    }

    /// The menu offers the panel once an address is set; the panel reports anything else missing.
    var hasAddress: Bool { !settings.proxmoxAddress.trimmingCharacters(in: .whitespaces).isEmpty }

    func showPanel() {
        let session = ProxmoxSession { [weak self] () throws(ProxmoxFailure) in
            guard let self else { throw .notConfigured }
            return try connection()
        }
        window.show(chrome: ProxmoxWindowChrome()) {
            ProxmoxPanelView(session: session).environment(core)
        }
    }

    func showSettings() {
        core.settingsCoordinator.showSettings(tab: .proxmox)
    }

    private func connection() throws(ProxmoxFailure) -> ProxmoxConnection {
        let tokenID = settings.proxmoxTokenID.trimmingCharacters(in: .whitespaces)
        guard hasAddress, !tokenID.isEmpty, let secret = storedSecret(), !secret.isEmpty else {
            throw .notConfigured
        }
        guard let baseURL = ProxmoxConnection.baseURL(from: settings.proxmoxAddress) else {
            throw .invalidAddress
        }
        return ProxmoxConnection(
            baseURL: baseURL, tokenID: tokenID, secret: secret,
            pinnedFingerprint: settings.proxmoxCertificateFingerprint)
    }

    // MARK: - Token secret

    var hasTokenSecret: Bool {
        (try? KeychainSecretStore.proxmox.hasSecret(for: Self.secretAccount)) ?? false
    }

    @discardableResult
    func saveTokenSecret(_ secret: String) -> Bool {
        do {
            try KeychainSecretStore.proxmox.setSecret(secret, for: Self.secretAccount)
            return true
        } catch {
            core.showMessage("Couldn't save the token secret to the Keychain", tone: .danger)
            return false
        }
    }

    func removeTokenSecret() {
        do {
            try KeychainSecretStore.proxmox.removeSecret(for: Self.secretAccount)
        } catch {
            core.showMessage("Couldn't remove the token secret from the Keychain", tone: .danger)
        }
    }

    private func storedSecret() -> String? {
        try? KeychainSecretStore.proxmox.secret(for: Self.secretAccount)
    }

    // MARK: - Certificate

    /// Pins the host's certificate only after the user compares its fingerprint and agrees.
    func trustCertificate() async {
        guard let baseURL = ProxmoxConnection.baseURL(from: settings.proxmoxAddress) else {
            core.showMessage(ProxmoxFailure.invalidAddress.message, tone: .danger)
            return
        }
        let certificate: ProxmoxCertificate
        do {
            certificate = try await ProxmoxService.certificate(at: baseURL)
        } catch {
            core.showMessage(error.message, tone: .danger)
            return
        }
        guard !certificate.isSystemTrusted else {
            settings.proxmoxCertificateFingerprint = nil
            core.showMessage("macOS already trusts this certificate")
            return
        }
        let trusted = await core.confirm(
            title: "Trust this certificate?",
            message: """
                Compare it with the SHA-256 fingerprint under System › Certificates in Proxmox.

                \(certificate.fingerprint)
                """,
            symbol: "lock.shield", confirmTitle: "Trust", tone: .neutral, confirmRole: .standard)
        guard trusted else { return }
        settings.proxmoxCertificateFingerprint = certificate.fingerprint
    }

    func forgetCertificate() {
        settings.proxmoxCertificateFingerprint = nil
    }
}
