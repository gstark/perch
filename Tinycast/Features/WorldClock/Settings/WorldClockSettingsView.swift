import SwiftUI

struct WorldClockSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var place = ""

    private var candidate: TimeZone? {
        WorldClockBoard.addable(place, zones: settings.worldClockZones, home: .autoupdatingCurrent)
    }

    var body: some View {
        Form {
            FeatureCommandsSection(owner: .worldClock, anchor: .worldClockCommands)

            Section {
                ForEach(WorldClockBoard.normalized(settings.worldClockZones), id: \.self) { identifier in
                    LabeledContent {
                        Button("Remove", systemImage: "minus.circle") {
                            settings.worldClockZones.removeAll { $0 == identifier }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    } label: {
                        Text(identifier.split(separator: "/").last.map(String.init)?
                            .replacingOccurrences(of: "_", with: " ") ?? identifier)
                        Text(identifier).foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    HStack {
                        TextField("City, country or airport", text: $place)
                            .labelsHidden()
                            .onSubmit(add)
                        Button("Add", action: add).disabled(candidate == nil)
                    }
                } label: {
                    SettingsRowTitle(.worldClockClocks, "Add a clock")
                    Text(candidate.map { "Adds \($0.identifier)." } ?? "Your Mac's own zone always comes first.")
                }
            } header: {
                SettingsSectionHeader(.worldClockClocks)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.worldClock)
    }

    private func add() {
        guard let candidate else { return }
        settings.worldClockZones.append(candidate.identifier)
        place = ""
    }
}
