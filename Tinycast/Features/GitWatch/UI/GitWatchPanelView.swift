import SwiftUI

/// Every at-risk repo by machine with its actions, then the ignored ones, dimmed, to bring back.
struct GitWatchPanelView: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        let coordinator = core.gitWatchCoordinator
        Form {
            Section {
                SettingsRow(
                    title: scanTitle, subtitle: "Scans every 10 minutes and after the Mac wakes."
                ) {
                    HStack(spacing: Theme.Spacing.md) {
                        Button("Settings…") { coordinator.showSettings() }
                        Button("Scan Now") { Task { await coordinator.scanNow() } }
                            .disabled(coordinator.isScanning)
                    }
                }
            }
            ForEach(core.settings.gitWatchMachines) { machine in
                GitWatchMachineSection(machine: machine)
            }
        }
        .formStyle(.grouped)
    }

    private var scanTitle: String {
        let coordinator = core.gitWatchCoordinator
        if coordinator.isScanning { return "Scanning…" }
        let count = coordinator.atRiskCount
        return count == 0 ? "Everything is pushed" : "\(count) \(count == 1 ? "repo" : "repos") to push"
    }
}

private struct GitWatchMachineSection: View {
    @Environment(AppCore.self) private var core
    let machine: GitWatchMachine

    var body: some View {
        let coordinator = core.gitWatchCoordinator
        let status = coordinator.statuses[machine.host]
        let pushed = Set((coordinator.pushes[machine.host] ?? [:]).keys)
        let entries = machine.entries(in: status?.report, keeping: pushed)
        Section {
            if entries.isEmpty {
                Text(status?.report == nil ? "Not scanned yet" : "Nothing to push")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                GitWatchEntryRow(entry: entry, machine: machine)
            }
        } header: {
            Text(machine.displayName + (status?.isStale == true ? " (stale)" : ""))
        } footer: {
            if let failure = status?.failure {
                Text("The last scan failed: \(failure.message)")
            }
        }
    }
}

private struct GitWatchEntryRow: View {
    /// Matches the menu bar meter's efficiency cores, the app's one other "present but quiet" look.
    private static let ignoredOpacity = MeterImage.efficiencyAlpha

    @Environment(AppCore.self) private var core
    let entry: GitWatchEntry
    let machine: GitWatchMachine

    var body: some View {
        let coordinator = core.gitWatchCoordinator
        let push = coordinator.pushes[machine.host]?[entry.path]
        SettingsRow(
            title: entry.name, subtitle: subtitle(push), subtitleLineLimit: 2,
            labelOpacity: entry.isIgnored ? Self.ignoredOpacity : 1
        ) {
            HStack(spacing: Theme.Spacing.md) {
                if entry.isIgnored {
                    Button("Unignore") { coordinator.unignore(entry.path, on: machine.host) }
                } else if let repo = entry.repo {
                    if machine.isLocal {
                        Button("Finder") { coordinator.openInFinder(repo) }
                            .help("Open in Finder")
                    } else {
                        Button("Copy ssh") { coordinator.copySSHCommand(repo, on: machine) }
                            .help("Copy an ssh command that opens a shell in this repository")
                    }
                    if push == .pushing {
                        ProgressView().controlSize(.small)
                    } else if push != .pushed {
                        Button("Push") { Task { await coordinator.push(repo, on: machine) } }
                            .help("Push \(repo.branch) to its remote. Perch never forces a push.")
                    }
                    Button("Ignore") { coordinator.ignore(entry.path, on: machine.host) }
                }
            }
        }
        .help(entry.path)
    }

    private func subtitle(_ push: GitWatchCoordinator.PushState?) -> String {
        switch push {
        case .pushing: return "Pushing…"
        case .pushed: return "Pushed \(entry.repo?.branch ?? "")"
        case .failed(let message): return "Push failed: \(message)"
        case nil:
            guard let repo = entry.repo else { return "Not found in the last scan" }
            return entry.isIgnored ? "Ignored · \(repo.summary)" : repo.summary
        }
    }
}
