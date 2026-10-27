import SwiftUI

struct ProcessLabelSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    /// Typed here and only written to the Keychain on Save, so a half-pasted token never lands.
    @State private var token = ""
    @State private var hasToken = false
    @State private var models = ModelsState.idle
    @State private var test = TestState.idle

    private enum ModelsState {
        case idle
        case loading
        case loaded([String])
        case failed(String)
    }

    private enum TestState {
        case idle
        case asking(String)
        case answered(question: String, answer: String)
        case failed(question: String, reason: String)
    }

    /// Long enough that typing an endpoint fetches once, not once per keystroke.
    private static let modelsFetchDelay: Duration = .milliseconds(600)

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
                modelRow
                tokenRow
                testRow
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
        .task(id: "\(settings.processLabelEndpoint)|\(hasToken)") {
            try? await Task.sleep(for: Self.modelsFetchDelay)
            guard !Task.isCancelled else { return }
            await loadModels()
        }
    }

    private func loadModels() async {
        guard ProcessLabelFormat.modelsEndpoint(from: settings.processLabelEndpoint) != nil else {
            models = .idle
            return
        }
        models = .loading
        do throws(ProcessLabelFailure) {
            let fetched = try await core.processLabelCoordinator.availableModels()
            guard !Task.isCancelled else { return }
            models = .loaded(fetched)
        } catch {
            guard !Task.isCancelled else { return }
            models = .failed(error.message)
        }
    }

    private var modelsStatus: String? {
        switch models {
        case .idle: return nil
        case .loading: return "Loading models…"
        case .loaded(let list) where list.isEmpty: return "The service lists no models"
        case .loaded(let list): return "\(list.count) models. Choose one with the list button."
        case .failed(let reason): return "Could not load models. \(reason)"
        }
    }

    private var listedModels: [String] {
        if case .loaded(let list) = models { return list }
        return []
    }

    private var modelRow: some View {
        @Bindable var settings = settings
        return LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                TextField(
                    "Model", text: $settings.processLabelModel,
                    prompt: Text("Choose or type a model"))
                    .labelsHidden()
                    .autocorrectionDisabled()
                Menu {
                    if let modelsStatus, listedModels.isEmpty {
                        Text(modelsStatus)
                    }
                    ForEach(listedModels, id: \.self) { model in
                        Button(model) { settings.processLabelModel = model }
                    }
                    Divider()
                    Button("Refresh") { Task { await loadModels() } }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose a model the service lists")
            }
        } label: {
            SettingsRowTitle(.processLabelsService, "Model")
            if let modelsStatus {
                Text(modelsStatus)
                    .foregroundStyle(
                        isModelsFailure ? Theme.Colors.warning : Theme.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder private var testRow: some View {
        let coordinator = core.processLabelCoordinator
        SettingsRow(
            title: "Test",
            subtitle: coordinator.isConfigured
                ? "Asks the model a question and shows the answer"
                : "Set an endpoint and a model first",
            anchor: .processLabelsService
        ) {
            Button("Ask") { ask() }
                .disabled(!coordinator.isConfigured || isAsking)
        }
        switch test {
        case .idle:
            EmptyView()
        case .asking(let question):
            exchange(question) { ProgressView().controlSize(.small) }
        case .answered(let question, let answer):
            exchange(question) { Text(answer).textSelection(.enabled) }
        case .failed(let question, let reason):
            exchange(question) { Text(reason).foregroundStyle(Theme.Colors.warning) }
        }
    }

    private func exchange(
        _ question: String, @ViewBuilder reply: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(question).foregroundStyle(Theme.Colors.textSecondary)
            reply()
        }
    }

    private var isModelsFailure: Bool {
        if case .failed = models { return true }
        return false
    }

    private var isAsking: Bool {
        if case .asking = test { return true }
        return false
    }

    private func ask() {
        let question = ProcessLabelFormat.testQuestions.randomElement() ?? ""
        test = .asking(question)
        Task {
            do throws(ProcessLabelFailure) {
                let answer = try await core.processLabelCoordinator.testAnswer(to: question)
                test = .answered(question: question, answer: answer)
            } catch {
                test = .failed(question: question, reason: error.message)
            }
        }
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
