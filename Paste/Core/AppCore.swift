import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    let settings = AppSettings()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    let palette = PaletteViewModel()
    let systemClipboardHistory = SystemClipboardHistory()

    private lazy var windowController = PaletteWindowController(core: self)
    private let activationPolicy = ActivationPolicyCoordinator()
    private lazy var auxWindows = AuxWindowController(activationPolicy: activationPolicy)
    private var aboutCloseToken: NotificationToken?
    private var transferTask: Task<Void, Never>?
    private var transferGeneration = UUID()
    private var selectionTask: Task<Void, Never>?

    private init() {
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
    }

    func start() {
        NerdSymbolsFont.register()
        activationPolicy.reset()
        settings.appearance.apply()

        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        Task { clipboardStore.load() }
        clipboardManager.start()

        KeyboardShortcuts.onKeyUp(for: .toggleClipboard) { [weak self] in
            self?.togglePalette()
        }
    }

    func togglePalette() {
        if windowController.isVisible {
            hidePalette()
        } else {
            showPalette()
        }
    }

    func showPalette() {
        palette.prepare()
        windowController.show()
    }

    func hidePalette(restoreFocus: Bool = true, cancelTransfer: Bool = true) {
        if cancelTransfer {
            transferTask?.cancel()
            transferTask = nil
            transferGeneration = UUID()
        }
        palette.imageQuickLookOpen = false
        ImageQuickLook.close()
        windowController.hide(restoreFocus: restoreFocus)
    }

    func handleReopen() {
        if auxWindows.focusExisting() { return }
        showPalette()
    }

    func showSettings(tab: SettingsTab = .general) {
        let isNew = auxWindows.show(
            id: "settings",
            title: String(localized: "Paste Settings", locale: settings.language.locale),
            size: CGSize(width: 440, height: 632),
            seamlessTitleBar: false
        ) {
            SettingsRootView(initialTab: tab)
        }
        if !isNew {
            NotificationCenter.default.post(name: .pasteSelectSettingsTab, object: tab)
        }
    }

    func showAbout() {
        activationPolicy.acquire("about")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [:])
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let window = NSApp.keyWindow else {
                self.activationPolicy.release("about")
                return
            }
            let token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.aboutCloseToken = nil
                    self?.activationPolicy.release("about")
                }
            }
            self.aboutCloseToken = NotificationToken(token, center: .default)
        }
    }

    func requestQuit() {
        let locale = settings.language.locale
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Quit Paste?", locale: locale)
        alert.informativeText = String(
            localized: "Paste will stop monitoring the clipboard until you open it again.",
            locale: locale
        )
        alert.addButton(withTitle: String(localized: "Quit", locale: locale))
        alert.addButton(withTitle: String(localized: "Cancel", locale: locale))
        alert.buttons.first?.hasDestructiveAction = true

        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        startTransfer { [weak self] generation in
            guard let self else { return }
            var hidden = false
            let succeeded = await Paster.paste(
                item, store: self.clipboardStore, previousApp: previous
            ) {
                hidden = true
                self.hidePalette(restoreFocus: false, cancelTransfer: false)
            }
            guard !Task.isCancelled else {
                if hidden { self.windowController.show() }
                return
            }
            if succeeded {
                self.select(item)
            } else if hidden {
                self.windowController.show()
            }
            self.finishTransfer(generation)
        }
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        startTransfer { [weak self] generation in
            guard let self else { return }
            if await Paster.pasteInPlace(item, store: self.clipboardStore, into: previous) {
                self.select(item)
            }
            self.finishTransfer(generation)
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        startTransfer { [weak self] generation in
            guard let self else { return }
            var hidden = false
            let succeeded = await Paster.copy(item, store: self.clipboardStore) {
                hidden = true
                self.hidePalette(restoreFocus: false, cancelTransfer: false)
            }
            guard !Task.isCancelled else {
                if hidden { self.windowController.show() }
                return
            }
            if succeeded {
                self.select(item)
            } else if hidden {
                self.windowController.show()
            }
            self.finishTransfer(generation)
        }
    }

    func togglePinnedClip(_ item: ClipboardItem) {
        clipboardStore.togglePinned(item)
        select(item, follow: true)
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func select(_ item: ClipboardItem, follow: Bool = false) {
        selectionTask?.cancel()
        let query = palette.query
        selectionTask = Task { [weak self] in
            guard let self else { return }
            let results = await self.clipboardStore.searchAsync(query)
            guard !Task.isCancelled, self.palette.query == query else { return }
            self.palette.selection = results.firstIndex { $0.id == item.id } ?? 0
            if follow { self.palette.followToken = UUID() }
        }
    }

    private func startTransfer(
        _ operation: @escaping @MainActor (_ generation: UUID) async -> Void
    ) {
        transferTask?.cancel()
        let generation = UUID()
        transferGeneration = generation
        transferTask = Task { await operation(generation) }
    }

    private func finishTransfer(_ generation: UUID) {
        guard transferGeneration == generation else { return }
        transferTask = nil
    }
}
