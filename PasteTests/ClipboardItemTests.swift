import XCTest

/// ClipboardItem value semantics: titles, matching, display kinds, and copy helpers.
final class ClipboardItemTests: XCTestCase {
    // MARK: - Titles

    func testDefaultTitleUsesFirstLine() {
        let item = ClipboardItem(text: "first line\nsecond line", sourceBundleID: nil)
        XCTAssertEqual(item.defaultTitle(locale: Locale(identifier: "en")), "first line")
    }

    func testDefaultTitleTrimsWhitespace() {
        let item = ClipboardItem(text: "   padded title   ", sourceBundleID: nil)
        XCTAssertEqual(item.defaultTitle(locale: Locale(identifier: "en")), "padded title")
    }

    func testDefaultTitleCapsAt200Characters() {
        let long = String(repeating: "x", count: 500)
        let item = ClipboardItem(text: long, sourceBundleID: nil)
        XCTAssertEqual(item.defaultTitle(locale: Locale(identifier: "en")).count, 200)
    }

    func testImageDefaultTitle() {
        let item = ClipboardItem(
            imagePath: "/tmp/x.png", imageFingerprint: "f", sourceBundleID: nil)
        XCTAssertEqual(item.defaultTitle(locale: Locale(identifier: "en")), "Image")
    }

    func testCustomTitleTakesPrecedence() {
        let item = ClipboardItem(text: "content", sourceBundleID: nil)
        let titled = item.withCustomTitle("My Name")
        XCTAssertEqual(titled.displayTitle(locale: Locale(identifier: "en")), "My Name")
    }

    func testBlankCustomTitleFallsBackToContent() {
        let item = ClipboardItem(text: "content", sourceBundleID: nil)
        XCTAssertEqual(
            item.withCustomTitle("   ").displayTitle(locale: Locale(identifier: "en")), "content")
        XCTAssertEqual(item.displayTitle(locale: Locale(identifier: "en")), "content")
    }

    // MARK: - Matching

    func testLiteralCaseInsensitiveMatch() {
        let item = ClipboardItem(text: "Hello World", sourceBundleID: nil)
        XCTAssertTrue(item.matches("hello"))
        XCTAssertTrue(item.matches("WORLD"))
        XCTAssertFalse(item.matches("goodbye"))
    }

    func testMatchAgainstCustomTitle() {
        let item = ClipboardItem(text: "some other content", sourceBundleID: nil)
            .withCustomTitle("important recipe")
        XCTAssertTrue(item.matches("recipe"))
        XCTAssertFalse(item.matches("unrelated"))
    }

    func testPinyinFullSpellingMatch() {
        let item = ClipboardItem(text: "你好世界", sourceBundleID: nil)
        // Contiguous syllable run only: "nihaoshijie" contains "nihao", not "nishijie".
        XCTAssertTrue(item.matches("nihao"))
        XCTAssertFalse(item.matches("nishijie"))
        XCTAssertFalse(item.matches("zaijian"))
    }

    func testPinyinInitialsMatch() {
        let item = ClipboardItem(text: "你好世界", sourceBundleID: nil)
        XCTAssertTrue(item.matches("nhsj"))
    }

    func testNonLatinQueryDoesNotUsePinyin() {
        let item = ClipboardItem(text: "你好世界", sourceBundleID: nil)
        // A Han query can only match literally.
        XCTAssertTrue(item.matches("你好"))
        // Not a literal substring, and pinyin matching is reserved for Latin queries.
        XCTAssertFalse(item.matches("世好"))
    }

    func testImageWithoutTextNeverMatches() {
        let item = ClipboardItem(
            imagePath: "/tmp/x.png", imageFingerprint: "f", sourceBundleID: nil)
        XCTAssertFalse(item.matches("anything"))
    }

    // MARK: - Copy helpers

    func testWithPinnedAtPreservesOtherFields() {
        let original = ClipboardItem(text: "keep me", sourceBundleID: "com.app")
        let stamp = Date()
        let pinned = original.with(pinnedAt: stamp)
        XCTAssertEqual(pinned.id, original.id)
        XCTAssertEqual(pinned.text, original.text)
        XCTAssertEqual(pinned.sourceBundleID, original.sourceBundleID)
        XCTAssertEqual(pinned.createdAt, original.createdAt)
        XCTAssertEqual(pinned.pinnedAt, stamp)
        XCTAssertTrue(pinned.isPinned)
        XCTAssertFalse(original.isPinned)
    }

    func testRefreshedUpdatesTimeAndSourceOnly() {
        let original = ClipboardItem(text: "same image", sourceBundleID: "com.old")
            .withCustomTitle("title")
        let refreshed = original.refreshed(sourceBundleID: "com.new")
        XCTAssertEqual(refreshed.id, original.id)
        XCTAssertEqual(refreshed.text, original.text)
        XCTAssertEqual(refreshed.customTitle, "title")
        XCTAssertEqual(refreshed.pinnedAt, original.pinnedAt)
        XCTAssertEqual(refreshed.sourceBundleID, "com.new")
        XCTAssertGreaterThan(refreshed.createdAt.timeIntervalSince1970, original.createdAt.timeIntervalSince1970 - 0.001)
    }
}
