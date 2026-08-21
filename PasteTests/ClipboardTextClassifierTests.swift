import XCTest

/// Clipboard content classification: links, code, and Markdown-article detection.
final class ClipboardTextClassifierTests: XCTestCase {
    // MARK: - Links

    func testWholeStringHTTPURLIsLink() {
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "https://example.com/a?b=c"), .link)
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "http://example.com"), .link)
        XCTAssertEqual(
            ClipboardTextClassifier.kind(for: "https://example.com:8080/path#frag"), .link)
    }

    func testURLWithSurroundingProseIsNotLink() {
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "see https://example.com"), .text)
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "https://example.com\nmore"), .text)
    }

    func testNonHTTPSchemeIsNotLink() {
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "ftp://example.com/file"), .text)
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "file:///tmp/x"), .text)
    }

    // MARK: - Code

    func testShebangIsCode() {
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "#!/bin/sh\necho hi"), .code)
    }

    func testJSONObjectIsCode() {
        XCTAssertEqual(ClipboardTextClassifier.kind(for: #"{"a": [1, 2, 3]}"#), .code)
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "[1, 2, 3]"), .code)
    }

    func testStandaloneFencedBlockIsCode() {
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "```swift\nlet a = 1\n```"), .code)
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "~~~\nplain\n~~~"), .code)
    }

    func testStrongSyntaxIsCode() {
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "const x = 1;\nconst y = 2;"), .code)
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "def greet(name):\n    return name"), .code)
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "SELECT id FROM users WHERE id = 1"), .code)
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "#include <stdio.h>\nint main() {}"), .code)
    }

    func testProseIsText() {
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "你好，今天天气不错。"), .text)
        XCTAssertEqual(
            ClipboardTextClassifier.kind(for: "Hello world.\nThis is a plain sentence."), .text)
    }

    func testInlineCodeInsideProseStaysText() {
        XCTAssertEqual(
            ClipboardTextClassifier.kind(for: "Use `return x` to exit early from the function."),
            .text)
    }

    func testMarkdownArticleWithFencesIsNotCode() {
        let article = """
        # Guide

        Here is an example:

        ```swift
        let a = 1
        ```

        That is all.
        """
        XCTAssertEqual(ClipboardTextClassifier.kind(for: article), .text)
        XCTAssertTrue(ClipboardTextClassifier.isMarkdownArticle(article))
    }

    func testShortStringsAreText() {
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "ab"), .text)
        XCTAssertEqual(ClipboardTextClassifier.kind(for: "  \n"), .text)
    }

    // MARK: - isMarkdownArticle

    func testMarkdownDetection() {
        XCTAssertTrue(ClipboardTextClassifier.isMarkdownArticle("# Title\n\nA paragraph."))
        XCTAssertTrue(ClipboardTextClassifier.isMarkdownArticle("A [link](https://example.com)."))
        XCTAssertFalse(ClipboardTextClassifier.isMarkdownArticle("Just a plain sentence."))
        XCTAssertFalse(ClipboardTextClassifier.isMarkdownArticle("const x = 1;"))
    }

    // MARK: - DisplayKind

    func testDisplayKindClassification() {
        XCTAssertEqual(
            ClipboardItem.DisplayKind.classify(kind: .image, text: nil), .image)
        XCTAssertEqual(
            ClipboardItem.DisplayKind.classify(kind: .link, text: "https://example.com"), .link)
        XCTAssertEqual(
            ClipboardItem.DisplayKind.classify(kind: .text, text: "# Title\n\nBody."), .markdown)
        XCTAssertEqual(
            ClipboardItem.DisplayKind.classify(kind: .text, text: "plain note"), .text)
        XCTAssertEqual(
            ClipboardItem.DisplayKind.classify(kind: .code, text: "# Title\n\nBody."), .markdown)
        XCTAssertEqual(
            ClipboardItem.DisplayKind.classify(kind: .code, text: "const x = 1;"), .code)
    }

    func testTypeLabels() {
        XCTAssertEqual(ClipboardItem.Kind.text.typeLabel, "Plain Text")
        XCTAssertEqual(ClipboardItem.Kind.code.typeLabel, "Code")
        XCTAssertEqual(ClipboardItem.Kind.link.typeLabel, "Link")
        XCTAssertEqual(ClipboardItem.Kind.image.typeLabel, "Image")
        XCTAssertEqual(ClipboardItem.DisplayKind.markdown.typeLabel, "Markdown")
    }
}
