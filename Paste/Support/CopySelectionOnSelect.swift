import AppKit
import SwiftUI

/// Read-only attributed preview text with select-to-copy. The scroll view and text system are
/// entirely AppKit so large previews do not need a SwiftUI `ScrollView` around `NSTextView`.
struct SelectableAttributedText: NSViewRepresentable {
    private enum Storage {
        case swiftUI(AttributedString)
        case appKit(NSAttributedString)
    }

    private let storage: Storage

    init(attributed: AttributedString) {
        storage = .swiftUI(attributed)
    }

    init(nsAttributed: NSAttributedString) {
        storage = .appKit(nsAttributed)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PreviewTextScrollView {
        let scrollView = PreviewTextScrollView()
        let textView = scrollView.textView
        textView.delegate = context.coordinator
        context.coordinator.onCopy = { Paster.copyString($0) }
        return scrollView
    }

    func updateNSView(_ scrollView: PreviewTextScrollView, context: Context) {
        context.coordinator.onCopy = { Paster.copyString($0) }
        let textView = scrollView.textView
        let ns: NSAttributedString
        switch storage {
        case .swiftUI(let attributed):
            ns = Self.nsAttributed(from: attributed, environment: context.environment)
        case .appKit(let attributed):
            ns = Self.nsAttributed(from: attributed)
        }
        let plain = ns.string
        if textView.string != plain {
            textView.textStorage?.setAttributedString(ns)
            textView.invalidateIntrinsicContentSize()
        } else if textView.selectedRange().length == 0, textView.currentAttributedString() != ns {
            textView.textStorage?.setAttributedString(ns)
        }
        scrollView.updateDocumentGeometry()
    }

    /// `AttributedString` stores the highlighters' colors in SwiftUI's attribute scope. The
    /// Foundation bridge does not turn those values into the `NSColor` attributes TextKit draws,
    /// so copy them explicitly while preserving every Foundation/AppKit attribute it can bridge.
    private static func nsAttributed(
        from attributed: AttributedString, environment: EnvironmentValues
    ) -> NSAttributedString {
        let size = NSFont.preferredFont(forTextStyle: .subheadline).pointSize
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let mutable = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        let full = NSRange(location: 0, length: mutable.length)
        guard full.length > 0 else { return mutable }

        var colorCache: [Color: NSColor] = [:]
        func appKitColor(_ color: Color) -> NSColor {
            if let cached = colorCache[color] { return cached }
            let resolved = nsColor(color, environment: environment)
            colorCache[color] = resolved
            return resolved
        }

        for run in attributed.runs {
            let range = NSRange(run.range, in: attributed)
            if let color = run.swiftUI.foregroundColor {
                mutable.addAttribute(
                    .foregroundColor, value: appKitColor(color),
                    range: range)
            }
            if let color = run.swiftUI.backgroundColor {
                mutable.addAttribute(
                    .backgroundColor, value: appKitColor(color),
                    range: range)
            }
        }

        mutable.enumerateAttribute(.font, in: full) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.font, value: font, range: range)
            }
        }
        mutable.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
        NerdSymbolsFont.applyFallback(to: mutable, baseFont: font)
        return mutable
    }

    /// Fully styled AppKit previews already contain their fonts and paragraph geometry. Fill only
    /// missing baseline attributes, preserving the renderer's layout verbatim.
    private static func nsAttributed(from attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: mutable.length)
        guard full.length > 0 else { return mutable }

        let font = NSFont.preferredFont(forTextStyle: .subheadline)
        mutable.enumerateAttribute(.font, in: full) { value, range, _ in
            if value == nil { mutable.addAttribute(.font, value: font, range: range) }
        }
        mutable.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
        NerdSymbolsFont.applyFallback(to: mutable, baseFont: font)
        return mutable
    }

    private static func nsColor(_ color: Color, environment: EnvironmentValues) -> NSColor {
        let resolved = color.resolve(in: environment)
        return NSColor(
            srgbRed: CGFloat(resolved.red), green: CGFloat(resolved.green),
            blue: CGFloat(resolved.blue), alpha: CGFloat(resolved.opacity))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onCopy: ((String) -> Void)?
        private var pending: String?

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let ns = textView.string as NSString
            guard range.length > 0, NSMaxRange(range) <= ns.length else {
                pending = nil
                return
            }
            let text = ns.substring(with: range)
            if NSEvent.pressedMouseButtons != 0 {
                pending = text
            } else {
                pending = nil
                onCopy?(text)
            }
        }

        func flushPending() {
            guard let pending else { return }
            self.pending = nil
            onCopy?(pending)
        }
    }
}

final class PreviewTextScrollView: NSScrollView {
    let textView = PreviewTextView()
    private var styleObserver: NotificationToken?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        scrollerStyle = .overlay
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        contentView.drawsBackground = false

        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            styleObserver = nil
            return
        }
        observeScrollerStyleChanges()
        applyOverlayScrollerStyle()
    }

    override func layout() {
        super.layout()
        updateDocumentGeometry()
    }

    func updateDocumentGeometry() {
        let width = contentSize.width
        guard width > 0, let textContainer = textView.textContainer else { return }

        textContainer.containerSize = NSSize(
            width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textContainer)
        let contentHeight = textView.intrinsicContentSize.height
        let height = max(contentSize.height, contentHeight)
        let size = NSSize(width: width, height: height)
        if textView.frame.size != size {
            textView.setFrameSize(size)
        }
    }

    private func observeScrollerStyleChanges() {
        guard styleObserver == nil else { return }
        let token = NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.applyOverlayScrollerStyle() }
        }
        styleObserver = NotificationToken(token, center: .default)
    }

    private func applyOverlayScrollerStyle() {
        guard scrollerStyle != .overlay || !autohidesScrollers || !hasVerticalScroller else {
            return
        }
        scrollerStyle = .overlay
        autohidesScrollers = true
        hasVerticalScroller = true
        tile()
    }
}

final class PreviewTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 0)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height))
    }

    override func layout() {
        super.layout()
        if let textContainer, abs(textContainer.size.width - bounds.width) > 0.5 {
            textContainer.size = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
            invalidateIntrinsicContentSize()
        }
    }

    /// Drop the default text-view junk (Look Up, Translate, Services, …); keep Copy + Select All.
    override func menu(for event: NSEvent) -> NSMenu? {
        let locale = AppCore.shared.settings.language.locale
        let menu = NSMenu()
        menu.addItem(
            withTitle: String(localized: "Copy", locale: locale), action: #selector(copy(_:)),
            keyEquivalent: "")
        menu.addItem(
            withTitle: String(localized: "Select All", locale: locale),
            action: #selector(selectAll(_:)), keyEquivalent: "")
        return menu
    }

    /// Same path as select-to-copy: stamp the internal pasteboard marker so monitoring skips history.
    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        let text = (string as NSString).substring(with: range)
        Paster.copyString(text)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        (delegate as? SelectableAttributedText.Coordinator)?.flushPending()
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    func currentAttributedString() -> NSAttributedString {
        textStorage.map { NSAttributedString(attributedString: $0) } ?? NSAttributedString()
    }
}
