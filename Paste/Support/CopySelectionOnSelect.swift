import AppKit
import SwiftUI

/// Read-only attributed preview text with select-to-copy. Uses a real `NSTextView` so
/// selection is observable (SwiftUI `Text` + `.textSelection` is not).
struct SelectableAttributedText: NSViewRepresentable {
    var attributed: AttributedString

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PreviewTextView {
        let textView = PreviewTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.onCopy = { Paster.copyString($0) }
        return textView
    }

    func updateNSView(_ textView: PreviewTextView, context: Context) {
        context.coordinator.onCopy = { Paster.copyString($0) }
        let ns = Self.nsAttributed(from: attributed, environment: context.environment)
        let plain = String(attributed.characters)
        if textView.string != plain {
            textView.textStorage?.setAttributedString(ns)
            textView.invalidateIntrinsicContentSize()
        } else if textView.selectedRange().length == 0, textView.currentAttributedString() != ns {
            textView.textStorage?.setAttributedString(ns)
        }
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
