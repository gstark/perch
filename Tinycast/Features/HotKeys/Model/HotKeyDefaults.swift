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
        .leftHalf: combo(kVK_LeftArrow, controlKey | optionKey),
        .rightHalf: combo(kVK_RightArrow, controlKey | optionKey),
        .topHalf: combo(kVK_UpArrow, controlKey | optionKey),
        .bottomHalf: combo(kVK_DownArrow, controlKey | optionKey),
        .maximize: combo(kVK_Return, controlKey | optionKey)
    ]

    private static func combo(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
        .combo(KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers))
    }
}
