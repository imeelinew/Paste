import Foundation
import SwiftUI

/// Lightweight multi-language highlighting for clipboard snippets. It intentionally colors only
/// lexical forms common across Swift, JavaScript/TypeScript, Python, C-family languages, Rust, Go,
/// SQL, shell, JSON, and markup; unknown syntax remains the native primary text color.
enum CodeSyntaxHighlighter {
    private struct Rule {
        let expression: NSRegularExpression
        let color: Color
    }

    private struct Token {
        let range: NSRange
        let color: Color
        let priority: Int
    }

    /// Rules are ordered for ties at the same UTF-16 offset. The scanner always consumes the
    /// earliest next token, so a quote before `//` wins as a string while a comment opener before
    /// a quote wins as a comment; tokens inside either are never recolored.
    private static let rules: [Rule] = [
        rule(#"(?m)^[\t ]*[#](?:include|define|if|ifdef|ifndef|endif|pragma|!)[^\n]*"#, .orange),
        rule(#"(?s:/\*.*?\*/)|(?m://[^\n]*|^[\t ]*[#][^\n]*)"#, .secondary),
        rule(#"`(?:\\.|[^`\\])*`|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, .red),
        rule(#"\b(?:0x[0-9A-Fa-f]+|0b[01]+|\d+(?:\.\d+)?)\b"#, .blue),
        rule(
            #"\b(?:import|from|export|default|as|const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|class|struct|enum|protocol|extension|func|guard|defer|throw|throws|try|catch|async|await|in|is|nil|self|super|true|false|null|undefined|new|typeof|instanceof|def|lambda|with|yield|pass|raise|public|private|protected|internal|static|final|override|mutating|where|associatedtype|some|any|interface|type|implements|extends|package|use|mod|pub|fn|match|impl|trait|dyn|SELECT|FROM|WHERE|JOIN|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|VALUES|INTO|AND|OR|NOT|AS|NULL)\b"#,
            .purple),
        rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, .teal),
        rule(#"\b[A-Za-z_$][A-Za-z0-9_$]*(?=[\t ]*\()"#, .indigo),
    ]

    private static func rule(_ pattern: String, _ color: Color) -> Rule {
        // Every pattern is a source literal covered by the render smoke test. Falling back to a
        // never-matching expression keeps a typo from crashing the app when a code row is selected.
        let expression =
            (try? NSRegularExpression(pattern: pattern))
            ?? (try! NSRegularExpression(pattern: "(?!)"))
        return Rule(expression: expression, color: color)
    }

    static func highlight(_ source: String) -> AttributedString {
        var output = AttributedString(source)
        output.foregroundColor = .primary
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)

        var tokens: [Token] = []
        for (priority, rule) in rules.enumerated() {
            for match in rule.expression.matches(in: source, range: fullRange) {
                tokens.append(Token(range: match.range, color: rule.color, priority: priority))
            }
        }
        tokens.sort {
            $0.range.location == $1.range.location
                ? $0.priority < $1.priority : $0.range.location < $1.range.location
        }

        var consumedThrough = 0
        for token in tokens {
            let tokenRange = token.range
            guard tokenRange.location >= consumedThrough else { continue }
            guard let stringRange = Range(tokenRange, in: source),
                let lower = AttributedString.Index(stringRange.lowerBound, within: output),
                let upper = AttributedString.Index(stringRange.upperBound, within: output)
            else { continue }
            output[lower..<upper].foregroundColor = token.color
            consumedThrough = NSMaxRange(tokenRange)
        }
        return output
    }
}

struct CodePreview: View {
    let code: String
    var query: String = ""
    @State private var highlighted: AttributedString?

    var body: some View {
        ScrollView {
            SelectableAttributedText(attributed: highlighted ?? AttributedString(code))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .overlayScroller()
        }
        .task(id: code + "\u{0}" + query) {
            var attributed = CodeSyntaxHighlighter.highlight(code)
            SearchHighlight.apply(to: &attributed, source: code, query: query)
            highlighted = attributed
        }
    }
}
