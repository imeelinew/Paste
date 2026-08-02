import AppKit
import Carbon.HIToolbox

enum Paster {
    /// Stamped on Paste's own synthetic keystrokes so listeners can ignore them.
    static let pasteEventTag: Int64 = 0x50415354  // "PAST"

    private enum Payload: Sendable {
        case text(String)
        case image(Data)
    }

    /// Prepare, target, write, and deliver as one ordered transaction. The caller hides the palette
    /// only after permission and payload preparation succeed; the item becomes recent only after a
    /// key event has been posted directly to the confirmed target process.
    @MainActor @discardableResult
    static func paste(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?,
        willDeliver: () -> Void
    ) async -> Bool {
        guard let app = previousApp, !app.isTerminated else { return false }
        let pid = app.processIdentifier
        return await PasteTransaction.run(
            permission: Permissions.ensureAccessibility,
            prepare: { await prepare(item, store: store) },
            willDeliver: willDeliver,
            targetReady: { await activateAndWait(app) },
            write: write,
            deliver: { postCommandV(toPid: pid, promptForPermission: false) },
            commit: { store.promote(item) })
    }

    /// Put the item on the pasteboard without pasting. Image bytes are loaded before the caller
    /// hides the palette, so a missing or large file never creates a blank-looking action.
    @MainActor @discardableResult
    static func copy(
        _ item: ClipboardItem, store: ClipboardStore, willWrite: () -> Void
    ) async -> Bool {
        guard let payload = await prepare(item, store: store), !Task.isCancelled else { return false }
        willWrite()
        guard write(payload) else { return false }
        store.promote(item)
        return true
    }

    /// Put a plain string on the pasteboard *without* the internal marker, so it flows into
    /// clipboard history like any other external copy.
    @MainActor
    static func copyPlainText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString(text, forType: .string)
    }

    /// String counterpart of the normal paste transaction.
    @MainActor @discardableResult
    static func pasteString(
        _ text: String, previousApp: NSRunningApplication?, willDeliver: () -> Void
    ) async -> Bool {
        guard let app = previousApp, !app.isTerminated else { return false }
        let pid = app.processIdentifier
        return await PasteTransaction.run(
            permission: Permissions.ensureAccessibility,
            prepare: { Payload.text(text) },
            willDeliver: willDeliver,
            targetReady: { await activateAndWait(app) },
            write: write,
            deliver: { postCommandV(toPid: pid, promptForPermission: false) },
            commit: {})
    }

    /// String counterpart of `copy(_:store:willWrite:)`.
    @MainActor
    static func copyString(_ text: String) {
        _ = write(.text(text))
    }

    /// Paste into `app` without activating it, keeping the palette frontmost.
    @MainActor @discardableResult
    static func pasteInPlace(
        _ item: ClipboardItem, store: ClipboardStore, into app: NSRunningApplication?
    ) async -> Bool {
        guard let app, !app.isTerminated else { return false }
        let pid = app.processIdentifier
        return await PasteTransaction.run(
            permission: Permissions.ensureAccessibility,
            prepare: { await prepare(item, store: store) },
            willDeliver: {},
            targetReady: { !app.isTerminated },
            write: write,
            deliver: { postCommandV(toPid: pid, promptForPermission: false) },
            commit: { store.promote(item) })
    }

    @MainActor
    private static func prepare(_ item: ClipboardItem, store: ClipboardStore) async -> Payload? {
        switch item.kind {
        case .text, .code:
            return item.text.map(Payload.text)
        case .image:
            guard let url = store.imageURL(for: item) else { return nil }
            return await Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled,
                    let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
                else { return nil }
                return Payload.image(data)
            }.value
        }
    }

    /// Wait for the target's actual activation state instead of guessing with a fixed delay.
    @MainActor
    private static func activateAndWait(_ app: NSRunningApplication) async -> Bool {
        guard !app.isTerminated else { return false }
        if app.isActive { return true }
        guard app.activate() else { return false }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(800))
        while !app.isActive {
            guard !app.isTerminated, clock.now < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    /// The pasteboard is mutated only after payload and target preflight have succeeded.
    @MainActor @discardableResult
    private static func write(_ payload: Payload) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch payload {
        case .text(let text):
            pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
            guard pb.setString(text, forType: .string) else { return false }
        case .image(let data):
            pb.declareTypes([.png, ClipboardManager.internalType], owner: nil)
            guard pb.setData(data, forType: .png) else { return false }
        }
        return pb.setData(Data(), forType: ClipboardManager.internalType)
    }

    /// Synthesize ⌘V for one target process. Permission can be prompted for standalone callers;
    /// transactions pass `false` because they already checked before mutating any visible state.
    @MainActor @discardableResult
    static func postCommandV(toPid pid: pid_t? = nil, promptForPermission: Bool = true) -> Bool {
        let trusted =
            promptForPermission
            ? Permissions.ensureAccessibility() : Permissions.isAccessibilityTrusted()
        guard trusted else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: pasteEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: pasteEventTag)

        if let pid {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }
}
