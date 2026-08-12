import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

/// The sole keyboard gateway for the palette window. It receives key events before the current
/// first responder, so embedded AppKit views and SwiftUI focus changes cannot disable commands.
final class PalettePanel: NSPanel {
    weak var paletteViewModel: PaletteViewModel? {
        didSet {
            paletteViewModel?.onMenuOpenChanged = { [weak self] open in
                self?.setSearchCaretHidden(open)
            }
        }
    }

    private static let relevantModifiers: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift,
    ]

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, route(event) { return }
        super.sendEvent(event)
    }

    private func route(_ event: NSEvent) -> Bool {
        guard let paletteViewModel else { return false }
        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        let shortcut = KeyboardShortcuts.Shortcut(event: event)

        if modifiers == .command {
            switch keyCode {
            case kVK_ANSI_Comma:
                return handleOnce(.settings, event: event)
            case kVK_ANSI_Q:
                return handleOnce(.quit, event: event)
            case kVK_Delete:
                return paletteViewModel.handle(.clearQuery)
            default:
                break
            }
        }

        if PaletteShortcut.actions.matches(shortcut) {
            return handleOnce(.toggleActions, event: event)
        }
        if PaletteShortcut.copyToClipboard.matches(shortcut) {
            return handleOnce(.copy, event: event)
        }
        if PaletteShortcut.pinToScreen.matches(shortcut) {
            return handleOnce(.pinImageToScreen, event: event)
        }
        if PaletteShortcut.togglePin.matches(shortcut) {
            return handleOnce(.togglePin, event: event)
        }
        if PaletteShortcut.showInFinder.matches(shortcut) {
            return handleOnce(.revealInFinder, event: event)
        }

        if modifiers == .command {
            switch keyCode {
            case kVK_ANSI_C, kVK_ANSI_X, kVK_ANSI_V, kVK_ANSI_A:
                if handleEditingShortcut(keyCode) { return true }
            default:
                break
            }
        }

        if modifiers.isEmpty {
            switch keyCode {
            case kVK_DownArrow:
                return paletteViewModel.handle(.move(1))
            case kVK_UpArrow:
                return paletteViewModel.handle(.move(-1))
            case kVK_Return, kVK_ANSI_KeypadEnter:
                return handleOnce(.activate, event: event)
            case kVK_Escape:
                return paletteViewModel.handle(.cancel)
            case kVK_Space:
                if paletteViewModel.canToggleQuickLook {
                    return handleOnce(.toggleQuickLook, event: event)
                }
                // At an empty query, Space is a Quick Look gesture even when the selected item
                // cannot be previewed. Swallow it instead of starting a useless blank search.
                if paletteViewModel.queryIsEmpty { return true }
            default:
                break
            }
        }

        // An overlay menu is modal. Unsupported keys must not leak into the search editor or the
        // read-only preview behind it.
        return paletteViewModel.menuOpen
    }

    private func handleOnce(_ command: PaletteCommand, event: NSEvent) -> Bool {
        if event.isARepeat { return true }
        return paletteViewModel?.handle(command) ?? false
    }

    private func setSearchCaretHidden(_ hidden: Bool) {
        guard let editor = firstResponder as? NSTextView else { return }
        editor.insertionPointColor = hidden ? .clear : .textColor
        editor.updateInsertionPointStateAndRestartTimer(!hidden)
    }

    /// This accessory app has no visible Edit menu, so route standard editing commands to the
    /// active AppKit field editor ourselves.
    private func handleEditingShortcut(_ keyCode: Int) -> Bool {
        guard paletteViewModel?.menuOpen != true, let editor = firstResponder as? NSTextView else {
            return false
        }

        switch keyCode {
        case kVK_ANSI_C:
            guard editor.selectedRange().length > 0 else { return true }
            editor.copy(nil)
            if !(editor is PreviewTextView) {
                Paster.markCurrentPasteboardInternal()
            }
            return true
        case kVK_ANSI_X:
            guard editor.isEditable, editor.selectedRange().length > 0 else { return true }
            editor.cut(nil)
            Paster.markCurrentPasteboardInternal()
            return true
        case kVK_ANSI_V:
            guard editor.isEditable else { return true }
            editor.paste(nil)
            return true
        case kVK_ANSI_A:
            editor.selectAll(nil)
            return true
        default:
            return false
        }
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
