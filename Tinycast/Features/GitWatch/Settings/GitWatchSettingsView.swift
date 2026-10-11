import SwiftUI

struct GitWatchSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var newHost = ""

    private var coordinator: GitWatchCoordinator { core.gitWatchCoordinator }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Scan Now") { Task { await coordinator.scanNow() } }
                        .disabled(coordinator.isScanning)
                } label: {
                    SettingsRowTitle(.gitWatchScan, "Scan Now")
                    Text(coordinator.isScanning ? "Scanning…" : "Scans every machine that has roots.")
                }
            } header: {
                SettingsSectionHeader(.gitWatchScan)
            } footer: {
                Text("Perch scans every 10 minutes and after the Mac wakes. It never fetches or pushes.")
            }

            ForEach(settings.gitWatchMachines) { machine in
                machineSection(machine)
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.md) {
                        TextField("SSH Host", text: $newHost, prompt: Text("nas or user@host"))
                            .labelsHidden()
                            .autocorrectionDisabled()
                        Button("Add") {
                            if coordinator.addMachine(host: newHost) { newHost = "" }
                        }
                        .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } label: {
                    SettingsRowTitle(.gitWatchAddMachine, "SSH Host")
                }
            } header: {
                SettingsSectionHeader(.gitWatchAddMachine)
            } footer: {
                Text("The host must accept your SSH key with no prompt, and have sh, find and git.")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.gitWatch)
    }

    private func machineSection(_ machine: GitWatchMachine) -> some View {
        Section {
            ForEach(machine.roots.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.md) {
                    TextField("Root", text: rootBinding(machine.host, index), prompt: Text("~/dev"))
                        .labelsHidden()
                        .autocorrectionDisabled()
                    Button("Remove Root", systemImage: "minus.circle") {
                        coordinator.updateMachine(machine.host) { edited in
                            if edited.roots.indices.contains(index) { edited.roots.remove(at: index) }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            Button("Add Root") {
                coordinator.updateMachine(machine.host) { $0.roots.append("~/") }
            }
            if !machine.isLocal {
                Button("Remove \(machine.host)", role: .destructive) {
                    coordinator.removeMachine(host: machine.host)
                }
            }
        } header: {
            Text(machine.displayName)
        } footer: {
            Text(statusText(for: machine))
        }
    }

    private func rootBinding(_ host: String, _ index: Int) -> Binding<String> {
        Binding {
            let roots = settings.gitWatchMachines.first { $0.host == host }?.roots ?? []
            return roots.indices.contains(index) ? roots[index] : ""
        } set: { newValue in
            coordinator.updateMachine(host) { edited in
                if edited.roots.indices.contains(index) { edited.roots[index] = newValue }
            }
        }
    }

    private func statusText(for machine: GitWatchMachine) -> String {
        guard let status = coordinator.statuses[machine.host], let scannedAt = status.scannedAt else {
            return machine.roots.isEmpty ? "No roots, so Perch does not scan this machine." : "Not scanned yet."
        }
        let time = scannedAt.formatted(date: .omitted, time: .shortened)
        if let failure = status.failure { return "Failed at \(time): \(failure.message)" }
        guard let report = status.report else { return "" }
        var parts = ["Scanned at \(time)", "\(report.repos.count) repos", "\(report.atRisk.count) at risk"]
        if !report.missingRoots.isEmpty {
            parts.append("missing " + report.missingRoots.joined(separator: ", "))
        }
        if report.unparsedLineCount > 0 { parts.append("\(report.unparsedLineCount) unreadable lines") }
        return parts.joined(separator: " · ")
    }
}
