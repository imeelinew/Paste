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
        if let frontmost, frontmost.processIdentifier != NSRunningApplication.current.processIdentifier, !frontmost.isTerminated {
            previousApp = frontmost
        } else if previousApp == nil || previousApp?.isTerminated == true {
            previousApp = NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular
                && $0.processIdentifier != NSRunningApplication.current.processIdentifier
                && !$0.isTerminated
            }
        }
        let target = PasteTarget(app: previousApp)
        core.palette.pasteTarget = target
        if let path = target?.iconPath {
            _ = IconCache.icon(forFile: path)
        }

        let panel = ensurePanel()
        position(panel)
        panel.contentView?.layoutSubtreeIfNeeded()
        if core.settings.switchToEnglishInputOnOpen {
            InputSourceSwitcher.selectEnglish()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        panel.orderFrontRegardless()
        panel.requestSearchFocus()
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.requestSearchFocus()
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
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
