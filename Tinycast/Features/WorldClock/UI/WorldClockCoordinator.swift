import AppKit
import UniformTypeIdentifiers

/// Owns the saved clocks and the clipboard time conversion. See docs/features/world-clock.md.
@MainActor
final class WorldClockCoordinator {
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    /// The HUD that reports a clipboard with no time on it.
    private unowned let core: AppCore
    /// One read at a time: a second press cancels the OCR helper the first is waiting on.
    private var readTask: Task<Void, Never>?

    init(settings: AppSettings, paletteCoordinator: PaletteCoordinator, core: AppCore) {
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// The conversion target, autoupdating so a Mac that changes zone needs no relaunch.
    var calendar: Calendar { .autoupdatingCurrent }

    func showWorldClock() {
        paletteCoordinator.togglePalette(mode: .worldClock)
    }

    func addZone(_ zone: TimeZone) {
        guard !settings.worldClockZones.contains(zone.identifier) else { return }
        settings.worldClockZones.append(zone.identifier)
        core.palette.query = ""
        core.palette.selection = settings.worldClockZones.count
    }

    func removeZone(_ identifier: String) {
        settings.worldClockZones.removeAll { $0 == identifier }
    }

    func moveZone(_ identifier: String, by offset: Int) {
        guard let index = settings.worldClockZones.firstIndex(of: identifier) else { return }
        let target = index + offset
        guard settings.worldClockZones.indices.contains(target) else { return }
        settings.worldClockZones.swapAt(index, target)
    }

    /// Unmarked, so the copied clock enters history: it is text you meant to keep.
    func copy(_ row: WorldClockRow) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(row.copyText)
        core.showMessage("Copied \(row.time) \(row.city)")
    }

    /// Reads a time off the clipboard, from text or a screenshot, and opens the board at it.
    func convertClipboardTime() {
        readTask?.cancel()
        let pasteboard = NSPasteboard.general
        // A file first, as the clipboard poller does: Finder also puts the file's name on the string type.
        if let image = PasteboardFiles.urls(on: pasteboard).first(where: Self.isImage) {
            return recognize(image, writing: nil)
        }
        if let text = pasteboard.string(forType: .string) {
            return open(CalcZonedMoment.seed(from: text, now: Date(), calendar: calendar))
        }
        for (type, ext) in [(NSPasteboard.PasteboardType.png, "png"), (.tiff, "tiff")] {
            guard let data = pasteboard.data(forType: type) else { continue }
            let url = URL.temporaryDirectory.appendingPathComponent("perch-clock-\(UUID().uuidString).\(ext)")
            return recognize(url, writing: data)
        }
        core.showMessage("The clipboard holds no text or image", tone: .neutral)
    }

    private static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// `data` is a bare screenshot, written for the helper, which only reads files, and removed after.
    private func recognize(_ url: URL, writing data: Data?) {
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        core.showProgress("Reading the screenshot…")
        readTask = Task {
            do {
                defer { if data != nil { try? FileManager.default.removeItem(at: url) } }
                if let data { try await Task.detached { try data.write(to: url) }.value }
                let text = try await ClipboardTextWorker.extract(
                    at: url, isPDF: false, executable: ClipboardTextWorker.executable)
                core.hideProgress()
                open(CalcZonedMoment.seed(from: text, now: Date(), calendar: calendar))
            } catch is CancellationError {
            } catch {
                core.showMessage("Couldn’t read the screenshot", tone: .danger)
            }
        }
    }

    private func open(_ seed: String?) {
        guard let seed else {
            return core.showMessage("No date or time with a time zone on the clipboard", tone: .neutral)
        }
        paletteCoordinator.showPalette(mode: .worldClock, seeding: seed)
    }
}
