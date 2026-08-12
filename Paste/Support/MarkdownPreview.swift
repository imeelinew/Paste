import Foundation
import SwiftUI

/// Native Markdown rendering for ordinary clipboard text. Parsing runs off the main actor so an
/// unusually large entry cannot block selection changes; the raw source remains visible until the
/// rendered value is ready and remains the payload used by the clipboard actions.
struct MarkdownPreview: View {
    let source: String
    var query: String = ""

    @State private var rendered: NSAttributedString?

    /// Immutable after creation; only the main actor reads the value returned by the detached
    /// parser task.
    private struct SendableRendered: @unchecked Sendable {
        let value: NSAttributedString
    }

    private struct Request: Hashable {
        let source: String
        let query: String
    }

    var body: some View {
        Group {
            if let rendered {
                SelectableAttributedText(nsAttributed: rendered)
            } else {
                SelectableAttributedText(
                    attributed: SearchHighlight.attributed(source, query: query))
            }
        }
        .task(id: Request(source: source, query: query)) {
            rendered = nil
            let parsed = await Task.detached(priority: .userInitiated) {
                Self.render(source).map(SendableRendered.init)
            }.value
            guard !Task.isCancelled else { return }
            rendered = parsed.map {
                SearchHighlight.applying(to: $0.value, query: query)
            }
        }
    }

    private nonisolated static func render(_ source: String) -> NSAttributedString? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let semantic = try? AttributedString(markdown: source, options: options),
            containsFormatting(semantic)
        else { return nil }

        // Parsing directly to NSAttributedString preserves block presentation intents. Bridging
        // from Swift's AttributedString keeps inline styling but drops the information TextKit
        // needs to lay out headings, paragraphs, and lists.
        return try? NSAttributedString(markdown: source, options: options)
    }

    /// Full Markdown parsing can normalize otherwise ordinary whitespace. Keep genuinely plain
    /// text byte-for-byte identical by using the parsed value only when it contains a visible
    /// Markdown construct.
    private nonisolated static func containsFormatting(_ attributed: AttributedString) -> Bool {
        let inlineFormatting: InlinePresentationIntent = [
            .code, .emphasized, .stronglyEmphasized, .strikethrough, .lineBreak, .inlineHTML,
            .blockHTML,
        ]

        for run in attributed.runs {
            if run.link != nil { return true }
            if let intent = run.inlinePresentationIntent,
                !intent.intersection(inlineFormatting).isEmpty
            {
                return true
            }
            if let intent = run.presentationIntent,
                intent.components.contains(where: { component in
                    if case .paragraph = component.kind { return false }
                    return true
                })
            {
                return true
            }
        }
        return false
    }
}
