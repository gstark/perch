import SwiftUI

/// The launcher category for the standard folders, each of which opens a Finder window.
struct FoldersSettingsView: View {
    var body: some View {
        Form {
            LauncherCategorySwitchSection(kind: .folder, anchor: .foldersFolders)

            LauncherItemsSection(
                kind: .folder, anchor: .foldersFolders, searchPrompt: "Search Folders…")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.folders)
        .releasesFocusOnOutsideClick()
    }
}
