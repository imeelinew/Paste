import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Reference-counted ownership of the app's regular activation policy. Settings and About may
/// overlap; closing either one can no longer hide the Dock icon while the other still needs it or
/// leave the icon behind after the final auxiliary window closes.
@MainActor
final class ActivationPolicyCoordinator {
    private var leases = Set<String>()
    private let apply: (Bool) -> Void

    init(apply: @escaping (Bool) -> Void = { regular in
        NSApp.setActivationPolicy(regular ? .regular : .accessory)
    }) {
        self.apply = apply
    }

    func acquire(_ lease: String) {
        leases.insert(lease)
        apply(true)
    }

    func release(_ lease: String) {
        leases.remove(lease)
        apply(!leases.isEmpty)
    }

    func reset() {
        leases.removeAll()
        apply(false)
    }
}

@MainActor
final class AuxWindowController: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]
    private let activationPolicy: ActivationPolicyCoordinator

    init(activationPolicy: ActivationPolicyCoordinator) {
        self.activationPolicy = activationPolicy
    }

    @discardableResult
    func show<Content: View>(
        id: String, title: String, size: CGSize, seamlessTitleBar: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> Bool {
        let window: NSWindow
        let isNew: Bool
        if let existing = windows[id] {
            window = existing
            isNew = false
        } else {
            isNew = true
            var style: NSWindow.StyleMask = [.titled, .closable]
            if seamlessTitleBar { style.insert(.fullSizeContentView) }
            // `size` is the on-screen frame (title bar included), matching measured peer apps.
            let contentRect = NSWindow.contentRect(
                forFrameRect: NSRect(origin: .zero, size: size),
                styleMask: style
            )
            let auxiliaryWindow = AuxiliaryWindow(
                contentRect: contentRect,
                styleMask: style,
                backing: .buffered,
                defer: false
            )
            auxiliaryWindow.onHideShortcut = { [weak self, weak auxiliaryWindow] in
                guard let auxiliaryWindow else { return }
                self?.hide(auxiliaryWindow)
            }
            window = auxiliaryWindow
            window.title = title
            if seamlessTitleBar {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .visible
                window.isMovableByWindowBackground = true
            }
            window.styleMask.remove(.resizable)
            window.setFrame(NSRect(origin: .zero, size: size), display: false)
            window.minSize = size
            window.maxSize = size
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: content())
            hosting.sizingOptions = []
            window.contentView = hosting
            window.delegate = self
            window.center()
            windows[id] = window
        }

        window.title = title
        activationPolicy.acquire("aux-\(id)")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { window.makeKeyAndOrderFront(nil) }
        return isNew
    }

    @discardableResult
    func focusExisting() -> Bool {
        guard
            let entry = windows.first(where: { $0.value.isVisible }) ?? windows.first
        else { return false }
        let (id, window) = entry
        activationPolicy.acquire("aux-\(id)")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let id = windows.first(where: { $0.value === window })?.key
        else { return }
        windows.removeValue(forKey: id)
        activationPolicy.release("aux-\(id)")
    }

    private func hide(_ window: NSWindow) {
        window.orderOut(nil)
        if let id = windows.first(where: { $0.value === window })?.key {
            activationPolicy.release("aux-\(id)")
        }
    }
}

private final class AuxiliaryWindow: NSWindow {
    var onHideShortcut: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .keyDown,
            modifiers == .command,
            event.keyCode == kVK_ANSI_W
        {
            onHideShortcut?()
            return
        }
        super.sendEvent(event)
    }
}
