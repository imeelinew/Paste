import AppKit
import CoreGraphics
import SQLite3
import XCTest

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Shared fixtures for the Paste logic test suite. The test bundle compiles the tested sources
/// directly (no app host), so every helper here stays hermetic: throwaway directories, generated
/// image payloads, and raw SQLite seeding against a store-owned database file.
enum TestSupport {
    /// Unique throwaway directory; callers own removal via `removeTemporaryDirectory`.
    static func makeTemporaryDirectory(_ label: String) -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PasteTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Solid-color image payload. Distinct colors produce distinct bytes, hence distinct
    /// SHA-256 fingerprints in the clipboard store.
    static func makeImageData(
        format: NSBitmapImageRep.FileType,
        red: UInt8 = 255, green: UInt8 = 0, blue: UInt8 = 0
    ) -> Data {
        let width = 4
        let height = 4
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(
            CGColor(
                red: CGFloat(red) / 255, green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: format, properties: [:])!
    }

    static func makePNGData(red: UInt8 = 255, green: UInt8 = 0, blue: UInt8 = 0) -> Data {
        makeImageData(format: .png, red: red, green: green, blue: blue)
    }

    static func makeJPEGData(red: UInt8 = 255, green: UInt8 = 0, blue: UInt8 = 0) -> Data {
        makeImageData(format: .jpeg, red: red, green: green, blue: blue)
    }

    /// Insert a row straight into a store database, bypassing the store API. Used to age rows
    /// beyond what the public API can express (backdated `created_at`, preset pins).
    @discardableResult
    static func seedRow(
        dbURL: URL, id: UUID, text: String, createdAt: Date, pinnedAt: Date? = nil,
        imagePath: String? = nil
    ) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return false
        }
        defer { sqlite3_close_v2(db) }
        var stmt: OpaquePointer?
        let sql =
            """
            INSERT INTO items(
              id, kind, text, image_path, created_at, source_app, pinned_at,
              image_fingerprint, custom_title, pinyin, pinyin_initials
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?)
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, transientDestructor)
        sqlite3_bind_text(stmt, 2, "text", -1, transientDestructor)
        sqlite3_bind_text(stmt, 3, text, -1, transientDestructor)
        if let imagePath {
            sqlite3_bind_text(stmt, 4, imagePath, -1, transientDestructor)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_double(stmt, 5, createdAt.timeIntervalSince1970)
        sqlite3_bind_null(stmt, 6)
        if let pinnedAt {
            sqlite3_bind_double(stmt, 7, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        for index in 8...11 { sqlite3_bind_null(stmt, Int32(index)) }
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    /// Poll until `condition` holds or the timeout elapses; returns the final evaluation.
    static func waitFor(
        _ condition: @escaping () -> Bool, timeout: TimeInterval = 3
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
