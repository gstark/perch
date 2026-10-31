import SwiftUI

/// The roots, the age filter, and every project with build folders, grouped by kind.
struct CleanupPanelView: View {
    @Environment(AppCore.self) private var core
    @State private var topHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var fitPending = false

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
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
            // A grouped Form cannot pin headers, so this list draws the grouped look itself.
            ScrollView {
                // Hidden, not cleared, while a scan runs, so Cancel brings the last report back.
                if !coordinator.isScanning, let report = coordinator.report {
                    let projects = coordinator.age.projects(in: report, now: .now, calendar: .current)
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if projects.isEmpty {
                            Text("No project matches this filter.")
                                .foregroundStyle(.secondary)
                                .padding(Theme.Spacing.xxl)
                        }
                        ForEach(CleanupGroup.groups(projects)) { group in
                            CleanupGroupSection(group: group, coordinator: coordinator) {
                                headerHeight = $0
                                fitIfPending()
                            }
                        }
                    }
                    .padding(.bottom, Self.listBottomPadding)
                }
            }
        }
        .onChange(of: coordinator.fitRequest) {
            fitPending = true
            fitIfPending()
        }
    }

    private static let listBottomPadding = Theme.Spacing.xxl

    /// Every group starts folded, so the list is exactly one header per group.
    private func fitIfPending() {
        let coordinator = core.cleanupCoordinator
        guard fitPending, let report = coordinator.report else { return }
        let projects = coordinator.age.projects(in: report, now: .now, calendar: .current)
        let groups = CGFloat(CleanupGroup.groups(projects).count)
        // No group means no header will ever report a height, and nothing to fit.
        guard groups > 0 else {
            fitPending = false
            return
        }
        guard topHeight > 0, headerHeight > 0 else { return }
        fitPending = false
        coordinator.fitWindow(contentHeight: topHeight + groups * headerHeight + Self.listBottomPadding)
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
                    CleanupRemoveButtons(
                        subject: "the build items of every listed project", projects: listed,
                        coordinator: coordinator, titles: ("Trash All…", "Delete All…"))
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
    /// Every header has the same height, which the window fit multiplies by the group count.
    let onHeaderHeight: (CGFloat) -> Void

    var body: some View {
        Section {
            if coordinator.expandedGroups.contains(group.id) {
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
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeaderHeight($0) }
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
                    CleanupRemoveButtons(
                        subject: project.artifacts.map(\.name).joined(separator: ", "),
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
        let isExpanded = coordinator.expandedGroups.contains(group.id)
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
                        let size = Text(DiskBytes.text(group.reclaimable))
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("\(count) · \(size)")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(count)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapses the group" : "Expands the group")
            // Outside the button, so only the chevron, badge and text fold the group.
            Spacer()
            CleanupRemoveButtons(
                subject: "the build items of every \(title) project in this group",
                projects: group.projects, coordinator: coordinator)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// Trash and Delete side by side; the confirmation dialog, not a menu, is what stops a slip.
private struct CleanupRemoveButtons: View {
    /// What the buttons act on, for their help text, such as `.venv`.
    let subject: String
    let projects: [CleanupProject]
    let coordinator: CleanupCoordinator
    /// Nil draws the two icons alone.
    var titles: (trash: String, delete: String)?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            button(
                titles?.trash ?? "Move to Trash", systemImage: "trash",
                help: "Move \(subject) to the Trash", mode: .trash)
            button(
                titles?.delete ?? "Delete Immediately", systemImage: "xmark.bin",
                help: "Delete \(subject) now, without the Trash", mode: .delete)
            .foregroundStyle(.red)
        }
        .disabled(coordinator.isRemoving)
    }

    @ViewBuilder
    private func button(
        _ title: String, systemImage: String, help: String, mode: CleanupRemovalMode
    ) -> some View {
        let button = Button(title, systemImage: systemImage) { remove(mode) }.help(help)
        if titles == nil {
            button.labelStyle(.iconOnly).buttonStyle(.borderless)
        } else {
            button.labelStyle(.titleAndIcon)
        }
    }

    private func remove(_ mode: CleanupRemovalMode) {
        Task { await coordinator.remove(projects, mode: mode) }
    }
}
