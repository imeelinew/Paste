import AppKit
import SwiftUI

/// GitHub-flavored Markdown preview for ordinary clipboard text. Parsing and deterministic AppKit
/// layout run off the main actor; the raw source remains visible until the result is ready and
/// remains the payload used by clipboard actions.
struct MarkdownPreview: View {
    let source: String
    var query: String = ""

    @State private var rendered: NSAttributedString?

    /// Immutable after creation; only the main actor reads the value returned by the detached
    /// parser task.
    private struct SendableRendered: @unchecked Sendable {
        let value: NSAttributedString
    }

    var body: some View {
        Group {
            if let rendered {
                SelectableAttributedText(
                    nsAttributed: SearchHighlight.applying(to: rendered, query: query))
            } else {
                SelectableAttributedText(
                    attributed: SearchHighlight.attributed(source, query: query))
            }
        }
        .task(id: source) {
            rendered = nil
            let parsed = await Task.detached(priority: .userInitiated) {
                MarkdownAttributedRenderer.render(source).map(SendableRendered.init)
            }.value
            guard !Task.isCancelled else { return }
            rendered = parsed?.value
        }
    }
}
