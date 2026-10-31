import SwiftUI

/// The roots, the age filter, and every project with build folders, the most space first.
struct CleanupPanelView: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        @Bindable var coordinator = core.cleanupCoordinator
        VStack(spacing: 0) {
            // Sized to its content, so only the project list below it scrolls.
            Form {
                CleanupRootsSection(coordinator: coordinator)
                Section {
                    Picker("Unchanged For", selection: $coordinator.age) {
                        ForEach(CleanupAge.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    CleanupScanRow(coordinator: coordinator)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            Form {
                if let report = coordinator.report {
                    CleanupResultsSection(
                        projects: coordinator.age.projects(in: report, now: .now, calendar: .current),
                        coordinator: coordinator)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct CleanupRootsSection: View {
    let coordinator: CleanupCoordinator

    var body: some View {
        Section {
            if coordinator.roots.isEmpty {
                Text("Add a folder that holds your projects, such as ~/dev.")
                    .foregroundStyle(.secondary)
            }
            ForEach(coordinator.roots, id: \.self) { root in
                SettingsRow(title: root) {
                    Button("Remove", systemImage: "minus.circle") { coordinator.removeRoot(root) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Remove \(root)")
                }
            }
            Button("Add Folder…") { coordinator.addRoots() }
        } header: {
            Text("Folders")
        }
    }
}

private struct CleanupScanRow: View {
    let coordinator: CleanupCoordinator

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            if coordinator.isScanning {
                ProgressView().controlSize(.small)
                Button("Cancel") { coordinator.cancelScan() }
            } else {
                if !listed.isEmpty {
                    CleanupRemoveMenu(
                        title: "Move All to Trash…", projects: listed, coordinator: coordinator)
                }
                Button("Scan") { coordinator.startScan() }
                    .disabled(coordinator.roots.isEmpty || coordinator.isRemoving)
            }
        }
    }

    private var listed: [CleanupProject] {
        guard let report = coordinator.report else { return [] }
        return coordinator.age.projects(in: report, now: .now, calendar: .current)
    }

    private var title: String {
        if coordinator.isScanning { return coordinator.progress?.text ?? "Scanning…" }
        guard coordinator.report != nil else { return "Not scanned yet" }
        let bytes = listed.reduce(0) { $0 + $1.reclaimable }
        return "\(listed.count) projects, \(DiskBytes.text(bytes))"
    }

    private var subtitle: String {
        if coordinator.isScanning { return "Finds projects first, then sizes their build folders." }
        guard let report = coordinator.report else {
            return "A scan lists build folders. It deletes nothing."
        }
        let when = report.date.formatted(date: .omitted, time: .shortened)
        guard !report.unreadable.isEmpty else { return "Scanned at \(when)" }
        return "Scanned at \(when). \(report.unreadable.count) folders could not be read."
    }
}

private struct CleanupResultsSection: View {
    let projects: [CleanupProject]
    let coordinator: CleanupCoordinator

    var body: some View {
        Section {
            if projects.isEmpty {
                Text("No project matches this filter.").foregroundStyle(.secondary)
            }
            ForEach(projects) { project in
                SettingsRow(
                    title: CleanupRoots.abbreviate(project.path, home: NSHomeDirectory()),
                    subtitle: detail(project)
                ) {
                    Text(DiskBytes.text(project.reclaimable)).monospacedDigit()
                    CleanupRemoveMenu(title: nil, projects: [project], coordinator: coordinator)
                    Button("Show in Finder", systemImage: "magnifyingglass") {
                        coordinator.reveal(project)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                }
            }
        } header: {
            Text("Projects")
        }
    }

    private func detail(_ project: CleanupProject) -> String {
        let kinds = project.kinds.map(\.title).formatted(.list(type: .and))
        let folders = project.artifacts.map(\.name).joined(separator: ", ")
        let changed = project.lastModified.formatted(.relative(presentation: .named))
        return "\(kinds) · \(folders) · changed \(changed)"
    }
}

/// Move to Trash on a click; Delete Immediately waits in the menu, so it is never the easy one.
private struct CleanupRemoveMenu: View {
    /// Nil draws the trash icon alone, for a row.
    let title: String?
    let projects: [CleanupProject]
    let coordinator: CleanupCoordinator

    var body: some View {
        Menu {
            Button("Delete Immediately…", role: .destructive) { remove(.delete) }
        } label: {
            if let title {
                Text(title)
            } else {
                Label("Move to Trash", systemImage: "trash").labelStyle(.iconOnly)
            }
        } primaryAction: {
            remove(.trash)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .disabled(coordinator.isRemoving)
        .help(
            title == nil
                ? "Move build folders to the Trash"
                : "Move the build folders of every listed project to the Trash")
    }

    private func remove(_ mode: CleanupRemovalMode) {
        Task { await coordinator.remove(projects, mode: mode) }
    }
}
