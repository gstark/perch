import SwiftUI

/// The roots, the age filter, and every project with build folders, grouped by kind.
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
            // A grouped Form cannot pin headers, so this list draws the grouped look itself.
            ScrollView {
                if let report = coordinator.report {
                    let projects = coordinator.age.projects(in: report, now: .now, calendar: .current)
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if projects.isEmpty {
                            Text("No project matches this filter.")
                                .foregroundStyle(.secondary)
                                .padding(Theme.Spacing.xxl)
                        }
                        ForEach(CleanupGroup.groups(projects)) { group in
                            CleanupGroupSection(group: group, coordinator: coordinator)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.xxl)
                }
            }
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
                        title: "Move All to Trash…",
                        help: "Move the build items of every listed project to the Trash",
                        projects: listed, coordinator: coordinator)
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

private struct CleanupGroupSection: View {
    let group: CleanupGroup
    let coordinator: CleanupCoordinator

    var body: some View {
        Section {
            if !coordinator.collapsedGroups.contains(group.id) {
                CleanupGroupCard(projects: group.projects, coordinator: coordinator)
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.bottom, Theme.Spacing.lg)
            }
        } header: {
            CleanupGroupHeader(group: group, coordinator: coordinator)
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.vertical, Theme.Spacing.sm)
                // Opaque, so rows scrolling under the pinned header never show through it.
                .background(.background)
        }
    }
}

/// The group's rows on one rounded card, as a grouped Form draws a section.
private struct CleanupGroupCard: View {
    let projects: [CleanupProject]
    let coordinator: CleanupCoordinator

    var body: some View {
        VStack(spacing: 0) {
            ForEach(projects) { project in
                if project.id != projects.first?.id { Divider() }
                // The title is what goes, so the button beside it never reads as the whole project.
                SettingsRow(
                    title: project.artifacts.map(\.name).joined(separator: ", "),
                    subtitle: detail(project)
                ) {
                    CleanupKindBadge(kind: project.primaryKind)
                } trailing: {
                    Text(DiskBytes.text(project.reclaimable)).monospacedDigit()
                    CleanupRemoveMenu(
                        title: trashTitle(project), help: "Move these build items to the Trash",
                        projects: [project], coordinator: coordinator)
                    Button("Show in Finder", systemImage: "magnifyingglass") {
                        coordinator.reveal(project)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                }
                .padding(.vertical, Theme.Spacing.md)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .background(Theme.Colors.cardFill, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.Colors.cardStroke))
    }

    private func trashTitle(_ project: CleanupProject) -> String {
        guard project.artifacts.count == 1, let only = project.artifacts.first else {
            return "Trash \(project.artifacts.count) items"
        }
        return "Trash \(only.name)"
    }

    private func detail(_ project: CleanupProject) -> String {
        let path = CleanupRoots.abbreviate(project.path, home: NSHomeDirectory())
        let changed = project.lastModified.formatted(.relative(presentation: .named))
        var detail = "in \(path) · changed \(changed)"
        // The group header names the kind; only a project of several kinds says more.
        if project.kinds.count > 1 {
            detail += " · " + project.kinds.map(\.title).formatted(.list(type: .and))
        }
        switch project.nestedProjects {
        case 0: return detail
        case 1: return detail + " · holds 1 other project"
        default: return detail + " · holds \(project.nestedProjects) other projects"
        }
    }
}

/// The kind's badge and name, its projects and space, and one button for the whole group.
private struct CleanupGroupHeader: View {
    let group: CleanupGroup
    let coordinator: CleanupCoordinator

    var body: some View {
        let title = group.kind?.title ?? "Other"
        let count = group.projects.count == 1 ? "1 project" : "\(group.projects.count) projects"
        let isExpanded = !coordinator.collapsedGroups.contains(group.id)
        HStack(spacing: Theme.Spacing.md) {
            Button {
                withAnimation(.snappy) { coordinator.toggleGroup(group.id) }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    CleanupKindBadge(kind: group.kind, isHeader: true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(title).font(.headline)
                        Text("\(count) · \(DiskBytes.text(group.reclaimable))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(count)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapses the group" : "Expands the group")
            CleanupRemoveMenu(
                title: "Trash All \(title)",
                help: "Move the build items of every \(title) project in this group to the Trash",
                projects: group.projects, coordinator: coordinator)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// Move to Trash on a click; Delete Immediately waits in the menu, so it is never the easy one.
private struct CleanupRemoveMenu: View {
    let title: String
    let help: String
    let projects: [CleanupProject]
    let coordinator: CleanupCoordinator

    var body: some View {
        Menu {
            Button("Delete Immediately…", role: .destructive) { remove(.delete) }
        } label: {
            Text(title)
        } primaryAction: {
            remove(.trash)
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(coordinator.isRemoving)
        .help(help)
    }

    private func remove(_ mode: CleanupRemovalMode) {
        Task { await coordinator.remove(projects, mode: mode) }
    }
}
