import AppKit

/// Owns colour delivery: the screen picker, and every copy in the notation Settings names.
@MainActor
final class ColorCoordinator {
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    /// The HUD that reports a picked colour.
    private unowned let core: AppCore
    /// A second sampler attaches to the open session, so a held chord would copy twice.
    private var pickTask: Task<Void, Never>?

    init(settings: AppSettings, paletteCoordinator: PaletteCoordinator, core: AppCore) {
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// What a colour is stated as and ↵ copies, so the two can never disagree.
    func preferredFormat(for color: ColorValue) -> ColorFormat {
        settings.colorNotation.format(for: color)
    }

    /// Unmarked, so a converted colour enters history itself: it is one you meant to keep.
    func copyColor(_ color: ColorValue, as format: ColorFormat) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.string(for: color))
    }

    func pickColor() {
        guard pickTask == nil else { return }
        // The palette would cover the pixels being picked; focus goes back to what is under it.
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: true) }
        pickTask = Task { [weak self] in
            let sampled = await NSColorSampler().sample()
            guard let self else { return }
            pickTask = nil
            guard let sampled else { return }
            guard let color = ColorValue(sampled: sampled) else {
                core.showMessage("Couldn't read that color", tone: .danger)
                return
            }
            let text = preferredFormat(for: color).string(for: color)
            Paster.copyPlainText(text)
            core.showMessage("Copied \(text)")
        }
    }
}

extension ColorValue {
    /// The sampler answers in the display's space, usually Display P3; every notation is sRGB.
    init?(sampled: NSColor) {
        guard let srgb = sampled.usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent,
            alpha: srgb.alphaComponent)
    }
}
