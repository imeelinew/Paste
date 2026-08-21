import XCTest

/// Pinyin romanization search: query shape detection and source-range mapping.
final class PinyinTests: XCTestCase {
    // MARK: - queryLooksLatin

    func testQueryLooksLatinAcceptsPinyinShapes() {
        XCTAssertTrue(Pinyin.queryLooksLatin("nihao"))
        XCTAssertTrue(Pinyin.queryLooksLatin("ni hao"))
        XCTAssertTrue(Pinyin.queryLooksLatin("ni'hao"))
        XCTAssertTrue(Pinyin.queryLooksLatin("Nihao"))
        XCTAssertTrue(Pinyin.queryLooksLatin("abc"))
    }

    func testQueryLooksLatinRejectsNonPinyinShapes() {
        XCTAssertFalse(Pinyin.queryLooksLatin(""))
        XCTAssertFalse(Pinyin.queryLooksLatin("   "))
        XCTAssertFalse(Pinyin.queryLooksLatin("你好"))
        XCTAssertFalse(Pinyin.queryLooksLatin("abc123"))
        XCTAssertFalse(Pinyin.queryLooksLatin("nihao!"))
        XCTAssertFalse(Pinyin.queryLooksLatin("héllo"))
    }

    // MARK: - matchingSourceRanges

    func testFullPinyinMatchesContiguousSyllables() {
        // Matching concatenates per-character syllables and requires a contiguous substring:
        // 你好世界 → "nihaoshijie", so "nihao" matches the first two characters.
        let ranges = Pinyin.matchingSourceRanges(query: "nihao", text: "你好世界")
        XCTAssertEqual(ranges.count, 1)
        guard let first = ranges.first else { return }
        XCTAssertEqual(String("你好世界"[first]), "你好")
    }

    func testFullPinyinAcrossSyllableBoundaryDoesNotMatch() {
        // "nishijie" spans 你好 + 世界 but is not a contiguous substring of "nihaoshijie".
        XCTAssertTrue(Pinyin.matchingSourceRanges(query: "nishijie", text: "你好世界").isEmpty)
    }

    func testInitialsMatchWholePhrase() {
        let ranges = Pinyin.matchingSourceRanges(query: "nhsj", text: "你好世界")
        XCTAssertEqual(ranges.count, 1)
        guard let first = ranges.first else { return }
        XCTAssertEqual(String("你好世界"[first]), "你好世界")
    }

    func testInitialsPrefixMatchesLeadingCharacters() {
        let ranges = Pinyin.matchingSourceRanges(query: "nh", text: "你好世界")
        XCTAssertEqual(ranges.count, 1)
        guard let first = ranges.first else { return }
        XCTAssertEqual(String("你好世界"[first]), "你好")
    }

    func testInitialsSuffixMatchesTrailingCharacters() {
        let ranges = Pinyin.matchingSourceRanges(query: "sj", text: "你好世界")
        XCTAssertEqual(ranges.count, 1)
        guard let first = ranges.first else { return }
        XCTAssertEqual(String("你好世界"[first]), "世界")
    }

    func testUnrelatedQueryProducesNoRanges() {
        XCTAssertTrue(Pinyin.matchingSourceRanges(query: "xyz", text: "你好世界").isEmpty)
        XCTAssertTrue(Pinyin.matchingSourceRanges(query: "", text: "你好世界").isEmpty)
    }

    func testNonHanTextProducesNoRanges() {
        XCTAssertTrue(Pinyin.matchingSourceRanges(query: "hello", text: "hello world").isEmpty)
    }

    func testMixedTextMapsOnlyHanCharacters() {
        let text = "说hi好"
        let ranges = Pinyin.matchingSourceRanges(query: "sh", text: text)
        XCTAssertEqual(ranges.count, 1)
        guard let first = ranges.first else { return }
        XCTAssertEqual(String(text[first]), "说")
    }

    func testCaseInsensitiveQuery() {
        let ranges = Pinyin.matchingSourceRanges(query: "NiHao", text: "你好世界")
        XCTAssertEqual(ranges.count, 1)
    }
}
