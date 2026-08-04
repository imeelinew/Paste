import AppKit
import Carbon.HIToolbox
import SwiftUI

final class PalettePanel: NSPanel {
    weak var paletteViewModel: PaletteViewModel? {
        didSet {
            paletteViewModel?.onMenuOpenChanged = { [weak self] open in
                self?.setSearchCaretHidden(open)
            }
        }
    }

    private static let menuNavKeys: Set<Int> = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab,
    ]

    private static let shortcutModifiers: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift,
    ]

    private func setSearchCaretHidden(_ hidden: Bool) {
        guard let editor = firstResponder as? NSTextView else { return }
        editor.insertionPointColor = hidden ? .clear : .textColor
        editor.updateInsertionPointStateAndRestartTimer(!hidden)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteViewModel?.hoverHighlightArmed = true
        case .keyDown: paletteViewModel?.hoverHighlightArmed = false
        default: break
        }
        if event.type == .keyDown,
            event.modifierFlags.intersection(Self.shortcutModifiers) == .command
        {
            switch Int(event.keyCode) {
            case kVK_ANSI_Comma:
                paletteViewModel?.requestAppMenuShortcut(.settings)
                return
            case kVK_ANSI_Q:
                paletteViewModel?.requestAppMenuShortcut(.quit)
                return
            case kVK_Delete:
                paletteViewModel?.requestActionsMenuShortcut(.delete)
                return
            default:
                break
            }
        }
        if event.type == .keyDown,
            paletteViewModel?.menuOpen == true,
            event.modifierFlags.intersection([.command, .control]).isEmpty,
            !Self.menuNavKeys.contains(Int(event.keyCode))
        {
            return
        }
        super.sendEvent(event)
    }

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0, width: Theme.Size.panelWidth, height: Theme.Size.panelHeight),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
