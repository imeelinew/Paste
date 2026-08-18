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
    private lazy var pinnedImageWindows = PinnedImageWindowController()
    private lazy var settingsWindowController = PasteSettingsWindowController(
        activationPolicy: activationPolicy
    )
    private lazy var menuBarController = MenuBarController(settings: settings)
    private let copySoundPlayer = CopySoundPlayer()
    private var controller: PasteController?
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
        clipboardStore.onItemInserted = { [weak self] in
            self?.handleClipboardItemInserted()
        }
        pinnedImageWindows.restore()
        clipboardManager.start()
        menuBarController.start()
        let controller = PasteController(core: self, cards: pinnedImageWindows)
        controller.start()
        self.controller = controller

        KeyboardShortcuts.onKeyUp(for: .toggleClipboard) { [weak self] in
            self?.togglePalette()
        }
        KeyboardShortcuts.onKeyUp(for: .hidePinnedCards) { [weak self] in
            self?.pinnedImageWindows.toggleParked()
        }
    }

    func handleControllerRequest(_ data: Data) async -> [String: Any] {
        guard let controller else {
            return PasteControllerIPC.response(ok: false, error: "Controller unavailable")
        }
        return await controller.handleRequest(data)
    }

    func prepareForTermination() {
        controller?.stop()
        pinnedImageWindows.flushPersistence()
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
        showPalette()
    }

    func showSettings(tab: SettingsTab = .general) {
        settingsWindowController.show(tab: tab)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func previewCopySound() {
        guard settings.soundEffectsEnabled else { return }
        copySoundPlayer.play(settings.copySoundEffect)
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
        startHidingTransfer(item) { [clipboardStore] willDeliver in
            await Paster.paste(
                item, store: clipboardStore, previousApp: previous, willDeliver: willDeliver)
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
        startHidingTransfer(item) { [clipboardStore] willWrite in
            await Paster.copy(item, store: clipboardStore, willWrite: willWrite)
        }
    }

    private func startHidingTransfer(
        _ item: ClipboardItem,
        operation: @escaping @MainActor (_ willHide: () -> Void) async -> Bool
    ) {
        startTransfer { [weak self] generation in
            guard let self else { return }
            var hidden = false
            let succeeded = await operation {
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

    func revealClipboardImage(_ item: ClipboardItem, dismissPalette: Bool = true) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        if dismissPalette { hidePalette(restoreFocus: false) }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func pinToScreen(_ item: ClipboardItem, dismissPalette: Bool = true) {
        let locale = settings.language.locale
        let title = item.displayTitle(locale: locale)
        switch item.kind {
        case .image:
            guard let url = clipboardStore.imageURL(for: item) else { return }
            if dismissPalette { hidePalette() }
            pinnedImageWindows.show(
                itemID: item.id,
                url: url,
                title: title,
                preferredLongEdge: { [weak settings] in
                    settings?.pinnedImageSize.longestEdge ?? PinnedImageSize.medium.longestEdge
                }
            )
        case .text, .code, .link:
            guard let text = item.text, !text.isEmpty else { return }
            let style: PinnedTextStyle
            if ClipboardTextClassifier.isMarkdownArticle(text) {
                style = .markdown
            } else if item.kind == .code {
                style = .code
            } else {
                style = .plain
            }
            if dismissPalette { hidePalette() }
            pinnedImageWindows.showText(
                itemID: item.id,
                text: text,
                style: style,
                title: title
            )
        }
    }

    private func handleClipboardItemInserted() {
        if settings.soundEffectsEnabled {
            copySoundPlayer.play(settings.copySoundEffect)
        }
        if settings.showMenuBarIcon && settings.animateMenuBarIconOnCopy {
            menuBarController.spin()
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
