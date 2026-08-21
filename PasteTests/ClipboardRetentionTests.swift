import XCTest

/// Retention option mapping: raw values persisted to UserDefaults and derived ages.
final class ClipboardRetentionTests: XCTestCase {
    func testRawValuesAreStable() {
        // Raw values are the persisted UserDefaults representation; changing them orphans
        // every existing user setting.
        XCTAssertEqual(ClipboardRetention.day.rawValue, 1)
        XCTAssertEqual(ClipboardRetention.week.rawValue, 7)
        XCTAssertEqual(ClipboardRetention.month.rawValue, 30)
        XCTAssertEqual(ClipboardRetention.threeMonths.rawValue, 90)
        XCTAssertEqual(ClipboardRetention.sixMonths.rawValue, 180)
        XCTAssertEqual(ClipboardRetention.year.rawValue, 365)
        XCTAssertEqual(ClipboardRetention.forever.rawValue, -1)
    }

    func testAllCasesCoverEveryOption() {
        XCTAssertEqual(ClipboardRetention.allCases.count, 7)
    }

    func testMaxAgeConvertsDaysToSeconds() {
        XCTAssertEqual(ClipboardRetention.day.maxAge, 86_400)
        XCTAssertEqual(ClipboardRetention.week.maxAge, 7 * 86_400)
        XCTAssertEqual(ClipboardRetention.month.maxAge, 30 * 86_400)
        XCTAssertEqual(ClipboardRetention.threeMonths.maxAge, 90 * 86_400)
        XCTAssertEqual(ClipboardRetention.sixMonths.maxAge, 180 * 86_400)
        XCTAssertEqual(ClipboardRetention.year.maxAge, 365 * 86_400)
    }

    func testForeverMaxAgeNeverExpires() {
        XCTAssertEqual(
            ClipboardRetention.forever.maxAge, TimeInterval.greatestFiniteMagnitude)
    }

    func testTitlesArePresent() {
        for option in ClipboardRetention.allCases {
            XCTAssertFalse(option.title.isEmpty)
        }
    }
}
