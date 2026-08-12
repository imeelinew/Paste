import AppKit
import KeyboardShortcuts
import SwiftUI

private enum PinnedImageCommand {
    case close
    case closeAll
    case dismiss
    case copy
    case zoomIn
    case zoomOut
    case resetSize

    var allowsKeyRepeat: Bool {
        self == .zoomIn || self == .zoomOut
    }
}

/// Owns transient image panels independently from the clipboard palette. Each clipboard image
/// gets at most one panel; pinning it again brings the existing panel forward.
@MainActor
final class PinnedImageWindowController: NSObject, NSWindowDelegate {
    private var panels: [ClipboardItem.ID: PinnedImagePanel] = [:]
    private var closingPanels: Set<ClipboardItem.ID> = []

    func show(itemID: ClipboardItem.ID, url: URL, title: String) {
        if let panel = panels[itemID] {
            activate(panel)
            return
        }

        let screen = targetScreen()
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_280, height: 800)
        let pixelSize = ImageThumbnail.pixelSize(of: url) ?? CGSize(width: 1_200, height: 900)
        let imageSize = NSImage(contentsOf: url)?.size ?? pixelSize
        let initialSize = PinnedImageLayout.initialSize(
            imageSize: imageSize,
            visibleFrame: visibleFrame
        )

        let panel = PinnedImagePanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.contentAspectRatio = imageSize
        panel.contentMinSize = PinnedImageLayout.minimumSize(
            imageSize: imageSize,
            visibleFrame: visibleFrame
        )
        panel.delegate = self
        panel.onCommand = { [weak self] command in
            self?.handle(command, itemID: itemID, url: url, imageSize: imageSize)
        }

        let decodeMaxPixel = NSScreen.screens.reduce(CGFloat(1_600)) { result, candidate in
            max(
                result,
                max(candidate.visibleFrame.width, candidate.visibleFrame.height)
                    * candidate.backingScaleFactor
            )
        }
        let hosting = NSHostingView(
            rootView: PinnedImageContent(
                url: url,
                decodeMaxPixel: decodeMaxPixel,
                onClose: { [weak self] in self?.close(itemID) }
            )
        )
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Theme.Radius.panel
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting

        let finalFrame = NSRect(
            x: visibleFrame.midX - initialSize.width / 2,
            y: visibleFrame.midY - initialSize.height / 2,
            width: initialSize.width,
            height: initialSize.height
        )
        panel.alphaValue = 0
        panel.setFrame(Self.scaledFrame(finalFrame, scale: 0.96), display: false)
        panels[itemID] = panel
        activate(panel)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    private func activate(_ panel: PinnedImagePanel) {
        // Trackpad gesture events are delivered to the active application. The clipboard palette
        // is intentionally non-activating, but an interactive pinned image cannot be: activating
        // here lets AppKit route physical magnify events to this window.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? PinnedImagePanel,
            let itemID = panels.first(where: { $0.value === panel })?.key
        else { return }
        panels.removeValue(forKey: itemID)
        closingPanels.remove(itemID)
    }

    private func close(_ itemID: ClipboardItem.ID) {
        guard let panel = panels[itemID], closingPanels.insert(itemID).inserted else { return }

        panel.ignoresMouseEvents = true
        let targetFrame = Self.scaledFrame(panel.frame, scale: 0.96)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
            panel.animator().setFrame(targetFrame, display: true)
        }

        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, let panel,
                closingPanels.contains(itemID), panels[itemID] === panel
            else { return }
            panel.close()
        }
    }

    private func handle(
        _ command: PinnedImageCommand,
        itemID: ClipboardItem.ID,
        url: URL,
        imageSize: CGSize
    ) {
        guard let panel = panels[itemID] else { return }

        switch command {
        case .close, .dismiss:
            close(itemID)
        case .closeAll:
            for id in Array(panels.keys) {
                close(id)
            }
        case .copy:
            Task { _ = await Paster.copyImage(at: url) }
        case .zoomIn:
            panel.resize(by: 1.1)
        case .zoomOut:
            panel.resize(by: 0.9)
        case .resetSize:
            resetSize(of: panel, imageSize: imageSize)
        }
    }

    private func resetSize(of panel: PinnedImagePanel, imageSize: CGSize) {
        let visibleFrame = panel.screen?.visibleFrame ?? targetScreen()?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_280, height: 800)
        let size = PinnedImageLayout.initialSize(
            imageSize: imageSize,
            visibleFrame: visibleFrame
        )
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let origin = CGPoint(
            x: min(max(center.x - size.width / 2, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(center.y - size.height / 2, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private static func scaledFrame(_ frame: NSRect, scale: CGFloat) -> NSRect {
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        return NSRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// Pure sizing policy kept separate from AppKit window ownership so unusual image ratios and
/// multi-display bounds remain deterministic.
enum PinnedImageLayout {
    static func initialSize(
        imageSize: CGSize, visibleFrame: CGRect
    ) -> CGSize {
        let natural = normalized(imageSize)
        let maxSize = CGSize(
            width: max(visibleFrame.width - 24, 1),
            height: max(visibleFrame.height - 24, 1)
        )
        let fitScale = min(maxSize.width / natural.width, maxSize.height / natural.height)
        let scale = max(min(fitScale, 1), 0.001)
        return rounded(CGSize(width: natural.width * scale, height: natural.height * scale))
    }

    static func minimumSize(imageSize: CGSize, visibleFrame: CGRect) -> CGSize {
        let natural = normalized(imageSize)
        let longSideScale = 160 / max(natural.width, natural.height)
        let shortSideScale = 44 / min(natural.width, natural.height)
        let desiredScale = max(longSideScale, shortSideScale)
        let displayScale = min(
            visibleFrame.width * 0.9 / natural.width,
            visibleFrame.height * 0.9 / natural.height
        )
        let scale = max(min(desiredScale, displayScale), 0.001)
        return rounded(CGSize(width: natural.width * scale, height: natural.height * scale))
    }

    private static func normalized(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )
    }

    private static func rounded(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width.rounded(), 1), height: max(size.height.rounded(), 1))
    }
}

private final class PinnedImagePanel: NSPanel {
    var onCommand: ((PinnedImageCommand) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let command = command(for: event) {
            if !event.isARepeat || command.allowsKeyRepeat {
                onCommand?(command)
            }
            return
        }
        if event.type == .magnify {
            resize(by: max(1 + event.magnification, 0.1))
            return
        }
        super.sendEvent(event)
    }

    func resize(by requestedScale: CGFloat) {
        guard requestedScale.isFinite, requestedScale > 0, requestedScale != 1 else { return }

        let current = frame
        guard current.width > 0, current.height > 0 else { return }

        let minimumScale = max(
            contentMinSize.width / current.width,
            contentMinSize.height / current.height
        )
        let scale = max(requestedScale, minimumScale)
        let size = CGSize(width: current.width * scale, height: current.height * scale)
        let resizedFrame = NSRect(
            x: current.midX - size.width / 2,
            y: current.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        setFrame(resizedFrame, display: true)
    }

    private func command(for event: NSEvent) -> PinnedImageCommand? {
        let shortcut = KeyboardShortcuts.Shortcut(event: event)
        if PinnedImageShortcut.close.matches(shortcut) { return .close }
        if PinnedImageShortcut.closeAll.matches(shortcut) { return .closeAll }
        if PinnedImageShortcut.dismiss.matches(shortcut) { return .dismiss }
        if PinnedImageShortcut.copy.matches(shortcut) { return .copy }
        if PinnedImageShortcut.zoomIn.matches(shortcut) { return .zoomIn }
        if PinnedImageShortcut.zoomOut.matches(shortcut) { return .zoomOut }
        if PinnedImageShortcut.resetSize.matches(shortcut) { return .resetSize }
        return nil
    }
}

@MainActor
private struct PinnedImageContent: View {
    let url: URL
    let decodeMaxPixel: CGFloat
    let onClose: () -> Void

    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if loadFailed {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            PinnedImageDragSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frosted(in: Circle())
            .accessibilityLabel(Text("Close Pinned Image"))
            .help(Text("Close Pinned Image"))
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .ignoresSafeArea()
        .task(id: url) {
            image = await ImageThumbnail.loadAsync(url, maxPixel: decodeMaxPixel)
            loadFailed = image == nil
        }
    }
}

private struct PinnedImageDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> PinnedImageDragView {
        PinnedImageDragView()
    }

    func updateNSView(_ nsView: PinnedImageDragView, context: Context) {}
}

private final class PinnedImageDragView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
