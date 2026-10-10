import SwiftUI

struct ProxmoxSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    /// Typed here and only written to the Keychain on Save, so a half-pasted secret never lands.
    @State private var secret = ""
    @State private var hasSecret = false
    @State private var isTrusting = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                TextField(text: $settings.proxmoxAddress, prompt: Text("pve.example.ts.net")) {
                    SettingsRowTitle(.proxmoxConnection, "Address")
                    Text("A bare host gets https and port 8006.")
                }
                .autocorrectionDisabled()
                TextField(text: $settings.proxmoxTokenID, prompt: Text("root@pam!perch")) {
                    SettingsRowTitle(.proxmoxConnection, "Token ID")
                }
                .autocorrectionDisabled()
                secretRow
            } header: {
                SettingsSectionHeader(.proxmoxConnection)
            } footer: {
                Text("Give the token the PVEAuditor role on /. Perch only reads.")
            }

            Section {
                certificateRow
            } header: {
                SettingsSectionHeader(.proxmoxCertificate)
            } footer: {
                Text("Needed only when macOS does not trust the host, as with Proxmox's own.")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.proxmox)
        .onAppear { hasSecret = core.proxmoxCoordinator.hasTokenSecret }
    }

    @ViewBuilder private var secretRow: some View {
        if hasSecret {
            SettingsRow(
                title: "Token Secret", subtitle: "Saved in the Keychain", anchor: .proxmoxConnection
            ) {
                Button("Remove") {
                    core.proxmoxCoordinator.removeTokenSecret()
                    hasSecret = core.proxmoxCoordinator.hasTokenSecret
                }
            }
        } else {
            LabeledContent {
                HStack(spacing: Theme.Spacing.md) {
                    RevealableSecureField(
                        title: "Token Secret", text: $secret, prompt: Text("Paste the secret")
                    )
                    .labelsHidden()
                    Button("Save") {
                        guard core.proxmoxCoordinator.saveTokenSecret(secret) else { return }
                        secret = ""
                        hasSecret = true
                    }
                    .disabled(secret.isEmpty)
                }
            } label: {
                SettingsRowTitle(.proxmoxConnection, "Token Secret")
            }
        }
    }

    private var certificateRow: some View {
        let fingerprint = settings.proxmoxCertificateFingerprint
        return SettingsRow(
            title: "Trusted Certificate", subtitle: fingerprint ?? "None", subtitleLineLimit: 2,
            anchor: .proxmoxCertificate
        ) {
            HStack(spacing: Theme.Spacing.md) {
                if fingerprint != nil {
                    Button("Forget") { core.proxmoxCoordinator.forgetCertificate() }
                }
                Button("Trust…") {
                    isTrusting = true
                    Task {
                        await core.proxmoxCoordinator.trustCertificate()
                        isTrusting = false
                    }
                }
                .disabled(isTrusting || !core.proxmoxCoordinator.hasAddress)
            }
        }
    }
}
