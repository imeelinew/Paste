import AppKit
import SwiftUI

@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    let settings = AppSettings()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    let hotKeys = HotKeyManager()
    let palette = PaletteViewModel()
    let installedApplications = InstalledApplications()

    private lazy var windowController = PaletteWindowController(core: self)
    private let auxWindows = AuxWindowController()

    private init() {
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
    }

    func start() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)

        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        Task { clipboardStore.load() }
        clipboardManager.start()

        hotKeys.onToggleClipboard = { [weak self] in self?.togglePalette() }
        hotKeys.start()
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

    func hidePalette(restoreFocus: Bool = true) {
        windowController.hide(restoreFocus: restoreFocus)
    }

    func handleReopen() {
        if auxWindows.focusExisting() { return }
        showPalette()
    }

    func showSettings(tab: SettingsTab = .clipboard) {
        let isNew = auxWindows.show(
            id: "settings", title: "Settings", size: CGSize(width: 720, height: 550),
            seamlessTitleBar: true
        ) {
            SettingsRootView(initialTab: tab)
                .environmentObject(self.installedApplications)
        }
        if !isNew {
            NotificationCenter.default.post(name: .pasteSelectSettingsTab, object: tab)
        }
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        if Paster.paste(item, store: clipboardStore, previousApp: previous) {
            select(item)
        }
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if windowController.pasteKeepingWindowOpen(item, store: clipboardStore) {
            select(item)
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        hidePalette(restoreFocus: false)
        if Paster.copy(item, store: clipboardStore) {
            select(item)
        }
    }

    func togglePinnedClip(_ item: ClipboardItem) {
        clipboardStore.togglePinned(item)
        select(item)
        palette.followToken = UUID()
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func select(_ item: ClipboardItem) {
        palette.selection = clipboardStore.rowIndex(of: item, in: palette.query) ?? 0
    }
}
