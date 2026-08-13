import AppKit
import SwiftUI

/// Lives outside `MarkdownPreview` so the byte-bounded parse cache is not MainActor-isolated.
private enum MarkdownPreviewCache {
    final class Entry: NSObject {
        let markdown: NSAttributedString?
        init(markdown: NSAttributedString?) { self.markdown = markdown }
    }

    final class Store: NSCache<NSString, Entry>, @unchecked Sendable {}

    static let shared: Store = {
        let cache = Store()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
}

/// GitHub-flavored Markdown preview for ordinary clipboard text. Parsing and deterministic AppKit
/// layout run off the main actor; the raw source remains visible until the result is ready and
/// remains the payload used by clipboard actions.
struct MarkdownPreview: View {
    let source: String
    var query: String = ""

    @State private var rendered: Rendered?

    private enum Rendered: @unchecked Sendable {
        case swiftUI(AttributedString)
        case appKit(NSAttributedString)
    }

    private struct RenderID: Hashable {
        let source: String
        let query: String
    }

    private nonisolated static func render(_ source: String, query: String) -> Rendered {
        let key = source as NSString
        let markdown: NSAttributedString?
        if let cached = MarkdownPreviewCache.shared.object(forKey: key) {
            markdown = cached.markdown
        } else {
            markdown = MarkdownAttributedRenderer.render(source)
            MarkdownPreviewCache.shared.setObject(
                MarkdownPreviewCache.Entry(markdown: markdown), forKey: key,
                cost: max(source.utf8.count, markdown?.length ?? 0))
        }
        if let markdown {
            return .appKit(SearchHighlight.applying(to: markdown, query: query))
        }
        return .swiftUI(SearchHighlight.attributed(source, query: query))
    }

    var body: some View {
        Group {
            switch rendered {
            case .appKit(let value):
                SelectableAttributedText(nsAttributed: value)
            case .swiftUI(let value):
                SelectableAttributedText(attributed: value)
            case nil:
                SelectableAttributedText(attributed: AttributedString(source))
            }
        }
        .task(id: RenderID(source: source, query: query)) {
            rendered = nil
            let task = Task.detached(priority: .userInitiated) {
                Self.render(source, query: query)
            }
            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled else { return }
            rendered = result
        }
    }
}
