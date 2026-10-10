import AppKit

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let customWindowSizes = CustomWindowSizeStore()
    let clipboardStore = ClipboardStore()
    @ObservationIgnored private var clipboardTextIndexer: ClipboardTextIndexer?
    let clipboardManager: ClipboardManager
    let hotKeys = HotKeyManager()
    let hyperKeyTap = HyperKeyTap()
    let windowMover = WindowMover()
    let spaceSwitcher = SpaceSwitcher()
    let inputSourceSwitcher = InputSourceSwitcher()
    let settings: AppSettings
    /// Mirrors settings into settings.json; nil until the first app scan.
    @ObservationIgnored private var settingsFile: SettingsFileRepository?
    /// The file's launcher items, kept to apply a waiting record once its app is installed.
    @ObservationIgnored private var launcherSettingsFile: LauncherSettingsFile?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private let iconStyle = IconStyleMonitor()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let aliases = AliasStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let regionNumberFormat = RegionNumberFormatMonitor()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let pinnedEmoji = PinnedEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteState()
    let activationPolicy = ActivationPolicy()

    @ObservationIgnored private(set) lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, settings: settings, appIndex: appIndex,
        windowController: windowController)
    /// Its own window and lifecycle: neither coordinator shows or closes the other's surface.
    @ObservationIgnored private(set) lazy var settingsCoordinator = SettingsCoordinator(core: self)
    @ObservationIgnored private(set) lazy var windowCommandCoordinator = WindowCommandCoordinator(
        settings: settings, paletteCoordinator: paletteCoordinator, windowMover: windowMover,
        spaceSwitcher: spaceSwitcher, customSizes: customWindowSizes)
    @ObservationIgnored private(set) lazy var customWindowSizeCoordinator =
        CustomWindowSizeCoordinator(
            store: customWindowSizes, settings: settings, appIndex: appIndex, hotKeys: hotKeys,
            favorites: favorites, visibility: visibility, ranking: launcherRanking,
            aliases: aliases, core: self)
    @ObservationIgnored private(set) lazy var windowShortcutPresetCoordinator =
        WindowShortcutPresetCoordinator(hotKeys: hotKeys, core: self)

    @ObservationIgnored private(set) lazy var launcherCoordinator = LauncherCoordinator(
        ranking: launcherRanking, windowController: windowController,
        paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator,
        windowCommandCoordinator: windowCommandCoordinator,
        clipboardCoordinator: clipboardCoordinator)
    @ObservationIgnored private(set) lazy var clipboardCoordinator = ClipboardCoordinator(
        clipboardStore: clipboardStore, clipboardManager: clipboardManager, settings: settings,
        appIndex: appIndex, palette: palette, windowController: windowController,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var emojiCoordinator = EmojiCoordinator(
        frequentEmoji: frequentEmoji, settings: settings, windowController: windowController,
        paletteCoordinator: paletteCoordinator)
    @ObservationIgnored private(set) lazy var calculatorCoordinator = CalculatorCoordinator(
        calcHistory: calcHistory, paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var proxmoxCoordinator = ProxmoxCoordinator(core: self)
    @ObservationIgnored private(set) lazy var gitWatchCoordinator = GitWatchCoordinator(core: self)

    let cpuSampler = CPUSampler()
    @ObservationIgnored private(set) lazy var statusItem = StatusItemController(
        core: self, sampler: cpuSampler)
    @ObservationIgnored private lazy var windowController = PaletteWindowController(core: self)
    @ObservationIgnored private lazy var messageHUD = MessageHUDController(settings: settings)
    private(set) var isShowingDialog = false
    var isDimmingPaletteForDialog: Bool { isShowingDialog && windowController.isVisible }
    /// Every confirmation, report and prompt; it also stops a held hotkey stacking them.
    @ObservationIgnored private lazy var dialogs = DialogController(
        settings: settings,
        onPresentationChanged: { [weak self] isPresenting in
            guard let self else { return }
            isShowingDialog = isPresenting
        })
    private let healthTicker = HealthTicker()

    private init() {
        let launcherRanking = LauncherRankingStore()
        let settings = AppSettings()
        self.launcherRanking = launcherRanking
        self.settings = settings
        appIndex = AppIndex(ranking: launcherRanking, aliases: aliases)
        let clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        self.clipboardManager = clipboardManager
    }

    func start() {
        Signposts.interval("AppCore.start") {
            // Shorten AppKit's ~2–3s tooltip delay; registration domain, so a user default wins.
            UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
            NSApp.setActivationPolicy(.accessory)
            applyAppearance()
            observeEffectiveAppearance()
            statusItem.start()
            gitWatchCoordinator.start()
            pinnedEmoji.onPersistenceFailure = { [weak self] in
                self?.showMessage("Couldn't save Emoji & Symbols pins", tone: .danger)
            }

            appIndex.start(settings: settings)
            clipboardCoordinator.applyEnabled()
            applyWindowCommandsPresence()
            customWindowSizes.onChange = { [weak self] _ in
                self?.customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            }
            customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            Task { await appIndex.refresh() }
            Task { await emojiIndex.load(languages: Locale.preferredLanguages) }
            currencyRates.start()

            hyperKeyTap.healthTicker = healthTicker
            hotKeys.modifierTapMonitor.healthTicker = healthTicker

            hotKeys.onTogglePalette = { [weak self] in self?.paletteCoordinator.togglePalette() }
            hotKeys.onRunCommand = { [weak self] id in self?.launcherCoordinator.runCommand(id) }
            hotKeys.onRunWindowCommand = { [weak self] id in
                self?.windowCommandCoordinator.runWindowCommand(id: id)
            }
            hotKeys.onRunCustomWindowSize = { [weak self] id in
                self?.windowCommandCoordinator.runCustomWindowSize(id: id)
            }
            appIndex.onScan = { [weak self] in
                guard let self else { return }
                hotKeys.removeAppBindings(where: appIndex.isUninstalled)
                // After the first scan, so the file's apps and panes have entries to match.
                if settingsFile == nil {
                    startSettingsFile()
                } else if let launcherSettingsFile {
                    reportSettingsFileIssues(launcherSettingsFile.applyInstalled())
                }
            }
            hotKeys.displayName = { [weak self] action in self?.hotKeyDisplayName(for: action) }
            hotKeys.allowsAction = { [weak self] action in
                guard let self, visibility.allowsHotKey(action) else { return false }
                // A disabled feature drops its commands from the launcher; their shortcuts go too.
                guard case .command(let id) = action else { return true }
                return appIndex.isCommandEnabled(id)
            }
            KeyShortcut.displayedHyperChord = { [settings] in
                guard settings.hyperKey != .none else { return nil }
                return KeyShortcut.hyperChord(includesShift: settings.hyperKeyIncludesShift)
            }
            hotKeys.start(
                customWindowSizeIDs: Set(customWindowSizes.sizes.map(\.id)))
            // Keeps running while Carbon pauses: the recorder needs its rewritten flags.
            hyperKeyTap.start(settings: settings)

            observeFeatureSwitches()
        }
    }

    /// Clicking the Dock icon: raise whichever window is already open, else summon the launcher.
    func handleReopen() {
        if settingsCoordinator.focusExisting() { return }
        paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
    }

    /// The store-backed half of the conflict message; `HotKeyManager` names the catalogs itself.
    private func hotKeyDisplayName(for action: HotKeyAction) -> String? {
        switch action {
        case .app(let bundleID):
            return appIndex.apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
        case .settingsPane(let bundleID):
            return appIndex.apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?
                .name
        case .customWindowSize(let id):
            return customWindowSizes.size(id: id)?.name
        case .togglePalette, .command, .windowCommand:
            return nil
        }
    }

    /// Idempotent: both switches are tracked, and either one flipping re-runs the whole decision.
    func applyClipboardTextSearch() {
        guard settings.clipboardEnabled, settings.clipboardTextSearchEnabled else {
            clipboardStore.onItemsChanged = nil
            clipboardStore.onSearchResultsChanged = nil
            clipboardStore.setTextSearchEnabled(false)
            clipboardTextIndexer?.stop()
            return
        }
        guard clipboardStore.setTextSearchEnabled(true) else {
            showMessage("Couldn't enable text recognition for clipboard history.", tone: .danger)
            return
        }
        clipboardStore.setTextSearchActive(palette.isVisible)
        // Kept across a disable: the indexer reschedules itself once a cancelled run winds down.
        let indexer =
            clipboardTextIndexer
            ?? ClipboardTextIndexer(store: clipboardStore, canRun: { ClipboardTextIndexer.isSystemIdle })
        clipboardTextIndexer = indexer
        clipboardStore.onItemsChanged = { [weak indexer] in indexer?.schedule() }
        clipboardStore.onSearchResultsChanged = { [weak self] query, previous, current in
            self?.clipboardCoordinator.followSearchResults(query: query, previous: previous, current: current)
        }
        indexer.start()
    }

    func prepareForTermination() {
        settingsFile?.flush()
        cpuSampler.stop()
        clipboardTextIndexer?.stop()
        // Caps Lock first: its remap is the one teardown that outlives the process.
        hyperKeyTap.prepareForTermination()
        inputSourceSwitcher.endSession()
    }

    // MARK: - Feature switches

    private func observeFeatureSwitches() {
        track({ _ = $0.showInMenuBar }, reproject: { $0.statusItem.applyVisibility() })
        track({ _ = $0.gitWatchMachines }, reproject: { $0.gitWatchCoordinator.refreshStatusItem() })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowManagementShowInLauncher
            },
            reproject: {
                $0.applyWindowCommandsPresence()
                $0.customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            })
        track(
            { _ = $0.clipboardEnabled }, reproject: { $0.clipboardCoordinator.applyEnabled() })
        track(
            { _ = $0.clipboardTextSearchEnabled }, reproject: { $0.applyClipboardTextSearch() })
        // Not a feature switch, but the same re-projection: a combo has the chord's ⇧ bit baked in.
        track({ _ = $0.hyperKeyIncludesShift }, reproject: { $0.applyHyperChord() })
        track({ _ = $0.appearance }, reproject: { $0.applyAppearance() })
        track({ _ = $0.interfaceSize }, reproject: { $0.windowController.applyInterfaceSize() })
        // Settings panes did these on change; settings.json can change them with no pane open.
        track(
            { _ = $0.clipboardRetention },
            reproject: { $0.clipboardCoordinator.applyRetention($0.settings.clipboardRetention) })
    }

    /// `.system` resolves to `nil`, so AppKit follows macOS with nothing polling.
    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    /// IconCache is told here, not from `applyAppearance()`, which never fires under `.system`.
    private func observeEffectiveAppearance() {
        // Synchronous on main, so no row can cache a tile under the outgoing appearance's key.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial]) { app, _ in
            MainActor.assumeIsolated { IconCache.setDarkSurface(app.effectiveAppearance.isDark) }
        }
    }

    private func track(
        _ reads: @escaping @Sendable @MainActor (AppSettings) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        track(settings, reads, reproject: reproject)
    }

    /// Fires synchronously on main before the write lands, so the task re-arms and re-reads.
    private func track<Store: AnyObject & Sendable>(
        _ store: Store,
        _ reads: @escaping @Sendable @MainActor (Store) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        withObservationTracking {
            reads(store)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track(store, reads, reproject: reproject)
                reproject(self)
            }
        }
    }

    /// Without a Hyper key the chord means nothing, so a literal ⌃⌥⌘ combo is left as recorded.
    private func applyHyperChord() {
        guard settings.hyperKey != .none else { return }
        hotKeys.retargetHyperBindings(includesShift: settings.hyperKeyIncludesShift)
    }

    private func applyWindowCommandsPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setWindowCommandsVisible(visible)
    }

    // MARK: - Settings file

    /// Mirrors settings into settings.json from now on, applying the file's own first.
    private func startSettingsFile() {
        guard settingsFile == nil else { return }
        let shortcuts = HotKeySettingsFile(hotKeys: hotKeys)
        let launcher = LauncherSettingsFile(
            appIndex: appIndex, aliases: aliases, visibility: visibility, shortcuts: shortcuts)
        let file = SettingsFileRepository(
            fileURL: AppPaths.settingsFile(),
            bindings: SettingsFileSchema.bindings(
                settings: settings, shortcuts: shortcuts, launcher: launcher,
                windowManagement: WindowManagementSettingsFile(
                    sizes: customWindowSizes, aliases: aliases,
                    shortcuts: shortcuts)),
            commit: shortcuts.commit)
        file.onIssues = { [weak self] issues in self?.reportSettingsFileIssues(issues) }
        settingsFile = file
        launcherSettingsFile = launcher
        file.start(importing: true)
    }

    private func reportSettingsFileIssues(_ issues: [SettingsFileIssue]) {
        guard let summary = SettingsFileIssue.summary(issues) else { return }
        showMessage(summary, tone: .danger)
    }

    // MARK: - Dialogs, routed here so `dialogs` stays the single owner

    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {
        await dialogs.notice(title: title, message: message, symbol: symbol, tone: tone)
    }

    /// `tone` styles the glyph, `confirmRole` the button; separate on purpose.
    func confirm(
        title: String, message: String?, symbol: String?, confirmTitle: String,
        tone: DialogTone = .danger, confirmRole: DialogAction.Role = .destructive,
        dismissTitle: String = "Cancel"
    ) async -> Bool {
        await dialogs.confirm(
            title: title, message: message, symbol: symbol, tone: tone, confirmTitle: confirmTitle,
            confirmRole: confirmRole, dismissTitle: dismissTitle)
    }

    /// A question with more than two answers; the returned index is into `options`.
    func choose(
        title: String, message: String?, symbol: String?, options: [DialogAction],
        defaultIndex: Int, tone: DialogTone = .neutral
    ) async -> Int {
        await dialogs.choose(
            title: title, message: message, symbol: symbol, tone: tone, options: options,
            defaultIndex: defaultIndex)
    }

    /// A failure with one usable second option; `true` when the user takes it.
    func reportFailure(
        title: String, message: String, symbol: String, recovery: String?
    ) async
        -> Bool
    {
        await dialogs.reportFailure(
            title: title, message: message, symbol: symbol, recovery: recovery)
    }

    /// The transient success/info pill, so `messageHUD` stays single-owned alongside `dialogs`.
    func showMessage(_ message: String, tone: DialogTone = .success) {
        messageHUD.show(message: message, tone: tone)
    }

    /// The same pill with a spinner, for work the reader started and cannot otherwise see running.
    func showProgress(_ message: String, onCancel: (() -> Void)? = nil) {
        messageHUD.showProgress(message: message, onCancel: onCancel)
    }

    func hideProgress() {
        messageHUD.dismiss()
    }
}
