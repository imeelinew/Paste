import AppKit
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?

    init(core: AppCore) {
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = frontmost
        }
        core.palette.pasteTarget = PasteTarget(app: previousApp)
        core.palette.hoverHighlightArmed = false

        let panel = ensurePanel()
        position(panel)
        panel.contentView?.layoutSubtreeIfNeeded()
        if core.settings.switchToEnglishInputOnOpen {
            InputSourceSwitcher.selectEnglish()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide(restoreFocus: Bool) {
        panel?.orderOut(nil)
        ImageThumbnail.purgePreviews()
        if core.settings.switchToEnglishInputOnOpen {
            InputSourceSwitcher.restore()
        }
        if restoreFocus { previousApp?.activate() }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        core.hidePalette(restoreFocus: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.core.palette.focusToken = UUID()
        }
    }

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let root = RootPaletteView()
            .environmentObject(core)
            .environmentObject(core.palette)
            .environmentObject(core.clipboardStore)
        let panel = PalettePanel(rootView: root)
        panel.delegate = self
        panel.paletteViewModel = core.palette
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = targetScreen() else { return }
        let visible = screen.visibleFrame
        let topEdge = visible.maxY - visible.height * Theme.Size.paletteTopMarginFraction
        panel.setFrame(
            NSRect(
                x: visible.midX - Theme.Size.panelWidth / 2,
                y: topEdge - Theme.Size.panelHeight,
                width: Theme.Size.panelWidth,
                height: Theme.Size.panelHeight),
            display: true)
    }

    private func targetScreen() -> NSScreen? {
        guard core.settings.openOnCursorScreen else { return NSScreen.main }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
