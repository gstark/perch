import SwiftUI

struct ProcessLabelSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    /// Typed here and only written to the Keychain on Save, so a half-pasted token never lands.
    @State private var token = ""
    @State private var hasToken = false

    var body: some View {
        @Bindable var settings = settings
        let coordinator = core.processLabelCoordinator
        return Form {
            Section {
                TextField(
                    text: $settings.processLabelEndpoint,
                    prompt: Text(verbatim: "https://api.openai.com/v1")
                ) {
                    SettingsRowTitle(.processLabelsService, "Endpoint")
                    Text("Any OpenAI-compatible service. A bare host gets /v1.")
                }
                .autocorrectionDisabled()
                TextField(text: $settings.processLabelModel, prompt: Text("gpt-5-mini")) {
                    SettingsRowTitle(.processLabelsService, "Model")
                }
                .autocorrectionDisabled()
                tokenRow
                if let failure = coordinator.lastFailure {
                    Text(failure).foregroundStyle(Theme.Colors.warning)
                }
            } header: {
                SettingsSectionHeader(.processLabelsService)
            } footer: {
                Text("""
                    A process that stays in the CPU menu's top list for 5 seconds is described \
                    once. Perch sends its path, arguments, working directory and parent, with \
                    secrets and numbers removed. Apps are never sent.
                    """)
            }

            Section {
                SettingsRow(
                    title: "Saved Labels", subtitle: "\(coordinator.store.cache.count)",
                    anchor: .processLabelsCache
                ) {
                    Button("Clear") { Task { await coordinator.clearLabels() } }
                        .disabled(coordinator.store.cache.count == 0)
                }
            } header: {
                SettingsSectionHeader(.processLabelsCache)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.processLabels)
        .onAppear { hasToken = coordinator.hasToken }
        .onChange(of: settings.processLabelEndpoint) { coordinator.connectionChanged() }
        .onChange(of: settings.processLabelModel) { coordinator.connectionChanged() }
    }

    @ViewBuilder private var tokenRow: some View {
        let coordinator = core.processLabelCoordinator
        if hasToken {
            SettingsRow(
                title: "API Token", subtitle: "Saved in the Keychain",
                anchor: .processLabelsService
            ) {
                Button("Remove") {
                    coordinator.removeToken()
                    hasToken = coordinator.hasToken
                }
            }
        } else {
            LabeledContent {
                HStack(spacing: Theme.Spacing.md) {
                    RevealableSecureField(
                        title: "API Token", text: $token, prompt: Text("Not needed for Ollama")
                    )
                    .labelsHidden()
                    Button("Save") {
                        guard coordinator.saveToken(token) else { return }
                        token = ""
                        hasToken = true
                    }
                    .disabled(token.isEmpty)
                }
            } label: {
                SettingsRowTitle(.processLabelsService, "API Token")
            }
        }
    }
}
