import Foundation
import SwiftUI

/// Native Markdown rendering for ordinary clipboard text. Parsing runs off the main actor so an
/// unusually large entry cannot block selection changes; the raw source remains visible until the
/// rendered value is ready and remains the payload used by the clipboard actions.
struct MarkdownPreview: View {
    let source: String
    var query: String = ""

    @State private var rendered: AttributedString?

    private struct Request: Hashable {
        let source: String
        let query: String
    }

    var body: some View {
        SelectableAttributedText(attributed: rendered ?? AttributedString(source))
            .task(id: Request(source: source, query: query)) {
                rendered = nil
                var output = await Task.detached(priority: .userInitiated) {
                    Self.render(source)
                }.value
                guard !Task.isCancelled else { return }

                // Markdown removes its delimiters, so highlight against the rendered characters
                // instead of trying to reuse source-string ranges.
                let visibleText = String(output.characters)
                SearchHighlight.apply(to: &output, source: visibleText, query: query)
                rendered = output
            }
    }

    private nonisolated static func render(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: source, options: options),
            containsFormatting(parsed)
        else { return AttributedString(source) }
        return parsed
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
