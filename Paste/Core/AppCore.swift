import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    let settings = AppSettings()
    let updateService = UpdateService()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    lazy var palette = PaletteViewModel(core: self)
    let systemClipboardHistory = SystemClipboardHistory()

    private lazy var windowController = PaletteWindowController(core: self)
    private let activationPolicy = ActivationPolicyCoordinator()
    private lazy var auxWindows = AuxWindowController(activationPolicy: activationPolicy)
    private lazy var pinnedImageWindows = PinnedImageWindowController()
    private lazy var settingsWindowController = PasteSettingsWindowController(
        activationPolicy: activationPolicy
    )
    private var transferTask: Task<Void, Never>?
    private var transferGeneration = UUID()

    private init() {
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
    }

    func start() {
        NerdSymbolsFont.register()
        activationPolicy.reset()
        settings.appearance.apply()
        updateService.start()

        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        clipboardStore.load()
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
        if settingsWindowController.isVisible {
            settingsWindowController.focus()
            return
        }
        if auxWindows.focusExisting() { return }
        showPalette()
    }

    func showSettings(tab: SettingsTab = .general) {
        settingsWindowController.show(tab: tab)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func checkForUpdates() {
        updateService.checkForUpdates()
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
                self.palette.select(item.id)
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
                self.palette.select(item.id)
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
                self.palette.select(item.id)
            } else if hidden {
                self.windowController.show()
            }
            self.finishTransfer(generation)
        }
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func pinImageToScreen(_ item: ClipboardItem) {
        guard item.kind == .image, let url = clipboardStore.imageURL(for: item) else { return }
        let title = String(localized: "Pinned Image", locale: settings.language.locale)
        hidePalette()
        pinnedImageWindows.show(
            itemID: item.id,
            url: url,
            title: title,
            preferredLongEdge: { [weak settings] in
                settings?.pinnedImageSize.longestEdge ?? PinnedImageSize.medium.longestEdge
            }
        )
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
