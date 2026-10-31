import SwiftUI

/// A project kind's glyph on a faint tile of its colour, as the Settings sidebar draws a tab.
struct CleanupKindBadge: View {
    /// A row repeats its group header's badge, so it stays small and quiet there.
    private static let rowOpacity = 0.6

    let kind: CleanupProjectKind?
    var isHeader = false

    var body: some View {
        SettingsTabIcon(
            systemImage: kind?.symbol ?? "folder", tint: kind?.tint ?? .secondary,
            size: isHeader ? Theme.Size.settingsRowIcon * 1.5 : Theme.Size.settingsRowIcon)
            .opacity(isHeader ? 1 : Self.rowOpacity)
            .help(kind?.title ?? "Project")
    }
}

extension CleanupProjectKind {
    /// No SF Symbol is a language logo, so each glyph is a nod to the ecosystem.
    fileprivate var symbol: String {
        switch self {
        case .node: "shippingbox.fill"
        case .reactNative: "atom"
        case .rails: "diamond.fill"
        case .cargo: "gearshape.2.fill"
        case .python: "lizard.fill"
        case .pythonEnvironment: "cube.transparent"
        case .swift: "swift"
        case .unity, .unreal: "gamecontroller.fill"
        case .godot: "gamecontroller"
        case .stack, .cabal: "function"
        case .sbt, .maven, .gradle: "cup.and.saucer.fill"
        case .cmake: "hammer.fill"
        case .jupyter: "book.pages.fill"
        case .pixi: "leaf.fill"
        case .composer: "music.note"
        case .pub: "bird.fill"
        case .elixir: "drop.fill"
        case .zig: "bolt.fill"
        case .dotnet: "number"
        case .turborepo: "bolt.horizontal.fill"
        case .terraform: "mountain.2.fill"
        case .cocoapods: "capsule.fill"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .node: .green
        case .reactNative, .pub: .cyan
        case .rails, .sbt, .cocoapods: .red
        case .cargo, .swift, .zig, .jupyter: .orange
        case .python, .pythonEnvironment, .godot: .blue
        case .unity, .cmake: .gray
        case .unreal: .indigo
        case .stack, .cabal, .elixir, .dotnet, .terraform: .purple
        case .maven, .composer: .brown
        case .gradle: .teal
        case .pixi: .yellow
        case .turborepo: .pink
        }
    }
}
