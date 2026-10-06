import AppKit
import SwiftUI

/// The Argument row: none, a file, a folder, or a URL.
struct WindowLayoutArgumentField: View {
    let draft: WindowLayoutDraft

    @State private var isEditingURL = false
    @State private var urlText = ""
    @FocusState private var isURLFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Argument")
                .font(.callout.weight(.medium))
            menu
            if isEditingURL {
                TextField("https://example.com", text: $urlText)
                    .textFieldStyle(.plain)
                    .focused($isURLFocused)
                    .focusEffectDisabled()
                    .layoutFieldChrome(isFocused: isURLFocused)
                    // Live for the same reason the number fields are: ⌘↵ never blurs this field.
                    .onChange(of: urlText) { _, typed in draft.setArgument(typed) }
            }
        }
    }

    private var menu: some View {
        Menu {
            Button("None") { clear() }
            Button("Choose File…") { choose(directories: false) }
            Button("Choose Folder…") { choose(directories: true) }
            Button("Enter URL…") {
                urlText = draft.selectedEntry?.argument ?? ""
                isEditingURL = true
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if let argument = draft.selectedEntry?.argument,
                    let destination = LinkDestination.detect(argument)
                {
                    Image(systemName: destination.defaultSymbol)
                    Text(destination.displayText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("None").foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.disclosure)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .layoutFieldChrome()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func clear() {
        isEditingURL = false
        urlText = ""
        draft.setArgument(nil)
    }

    private func choose(directories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        // An accessory app's panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isEditingURL = false
        draft.setArgument((url.path as NSString).abbreviatingWithTildeInPath)
    }
}
