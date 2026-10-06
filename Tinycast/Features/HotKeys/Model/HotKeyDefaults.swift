import Carbon.HIToolbox

/// The bindings a fresh install starts with. Clearing one stores `unbound`, so it stays cleared.
enum HotKeyDefaults {
    static let unbound = "unbound"

    static func binding(for action: HotKeyAction) -> HotKeyBinding? {
        switch action {
        case .togglePalette: combo(kVK_Space, cmdKey)
        case .windowCommand(let id): windowCommands[id]
        default: nil
        }
    }

    private static let windowCommands: [WindowCommand.ID: HotKeyBinding] = [
        .leftHalf: combo(kVK_LeftArrow, cmdKey | shiftKey),
        .rightHalf: combo(kVK_RightArrow, cmdKey | shiftKey),
        .topHalf: combo(kVK_UpArrow, cmdKey | shiftKey),
        .bottomHalf: combo(kVK_DownArrow, cmdKey | shiftKey),
        .maximize: combo(kVK_Return, cmdKey | shiftKey)
    ]

    private static func combo(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
        .combo(KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers))
    }
}
