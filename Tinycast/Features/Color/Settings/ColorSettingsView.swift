import SwiftUI

struct ColorSettingsView: View {
    @Environment(AppSettings.self) private var settings

    /// The orange the clipboard docs use, so the example reads like a real copied colour.
    private static let sample = ColorValue(red: 1, green: 87 / 255, blue: 51 / 255)

    var body: some View {
        @Bindable var settings = settings
        let example = settings.colorNotation.format(for: Self.sample).string(for: Self.sample)
        return Form {
            FeatureCommandsSection(owner: .colors, anchor: .colorsCommands)

            Section {
                Picker(selection: $settings.colorNotation) {
                    ForEach(ColorNotation.allCases) { notation in
                        Text(notation.title).tag(notation)
                    }
                } label: {
                    SettingsRowTitle(.colorsCopying, "Copy colors as")
                    Text("↵ on a color card and Pick Color copy \(example).")
                }
            } header: {
                SettingsSectionHeader(.colorsCopying)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.colors)
    }
}
