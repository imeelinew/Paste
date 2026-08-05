import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ClipboardItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case text, code, link, image

        /// Localization key for the Information "Type" row.
        var typeLabel: String {
            switch self {
            case .text: "Text"
            case .code: "Code"
            case .link: "Link"
            case .image: "Image"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let text: String?
    /// Absolute path to the image owned by this store.
    let imagePath: String?
    let createdAt: Date
    /// Bundle ID of the app frontmost when the copy was captured (see `ClipboardManager.poll`).
    let sourceBundleID: String?
    /// When the entry was pinned. Pinned entries lead the list newest-pin-first and are exempt from retention pruning.
    let pinnedAt: Date?

    var isPinned: Bool { pinnedAt != nil }

    init(text: String, sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: ClipboardTextClassifier.kind(for: text), text: text,
            imagePath: nil, createdAt: Date(),
            sourceBundleID: sourceBundleID)
    }

    init(imagePath: String, sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .image, text: nil, imagePath: imagePath, createdAt: Date(),
            sourceBundleID: sourceBundleID)
    }

    fileprivate init(
        id: UUID, kind: Kind, text: String?, imagePath: String?, createdAt: Date,
        sourceBundleID: String?, pinnedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.pinnedAt = pinnedAt
    }

    /// Copy with the two fields the store rewrites in place; the pin is stated outright because every rewrite either stamps it or drops the row back into the history.
    func with(createdAt: Date? = nil, pinnedAt: Date?) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath,
            createdAt: createdAt ?? self.createdAt, sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt)
    }

    /// Case-insensitive literal or pinyin match for resident and pinned entries.
    /// Latin-letter queries also match Mandarin pinyin (full spelling or initials) so `nihao` / `nh` can find `你好`.
    func matches(_ query: String) -> Bool {
        guard let text else { return false }
        if text.localizedCaseInsensitiveContains(query) { return true }
        guard Pinyin.queryLooksLatin(query) else { return false }
        return Pinyin.matches(query: query, text: text)
    }
}

/// Mandarin romanization helpers for clipboard search (Foundation/`CFStringTransform` only).
enum Pinyin {
    struct SearchForms: Sendable {
        let full: String
        let initials: String
    }

    /// True when `query` is ASCII letters/spaces/apostrophes — the shape of typed pinyin.
    static func queryLooksLatin(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var sawLetter = false
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                guard scalar.value <= 127 else { return false }
                sawLetter = true
            } else if !(CharacterSet.whitespaces.contains(scalar) || scalar == "'") {
                return false
            }
        }
        return sawLetter
    }

    fileprivate static func matches(query: String, text: String) -> Bool {
        !matchingSourceRanges(query: query, text: text).isEmpty
    }

    /// Source-character ranges whose Mandarin pinyin (full spelling or initials) contains `query`.
    static func matchingSourceRanges(query: String, text: String) -> [Range<String.Index>] {
        let q = compact(query)
        guard !q.isEmpty else { return [] }

        let syllables = syllables(of: text)
        guard !syllables.isEmpty else { return [] }

        var ranges = rangesMatching(
            query: q, syllables: syllables,
            token: \.compact)
        if ranges.isEmpty {
            ranges = rangesMatching(
                query: q, syllables: syllables,
                token: \.initial)
        }
        return ranges
    }

    private static func romanize(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String).lowercased()
    }

    /// Persistent search terms contain only Han characters. Latin text already has a literal FTS
    /// path, so excluding it avoids thousands of unnecessary Core Foundation transforms for the
    /// overwhelmingly common English query.
    fileprivate static func searchForms(for text: String) -> SearchForms {
        var full = ""
        var initials = ""
        for character in text where containsHan(character) {
            let syllable = compact(romanize(String(character)))
            guard !syllable.isEmpty else { continue }
            full += syllable
            initials.append(syllable.first!)
        }
        return SearchForms(full: full, initials: initials)
    }

    fileprivate static func containsHan(_ text: String) -> Bool {
        text.contains(where: containsHan)
    }

    private struct Syllable {
        let range: Range<String.Index>
        let compact: String
        let initial: String
    }

    private static func syllables(of text: String) -> [Syllable] {
        var result: [Syllable] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let unit = String(text[index..<next])
            guard containsHan(text[index]) else {
                index = next
                continue
            }
            let romanized = compact(romanize(unit))
            if !romanized.isEmpty {
                result.append(
                    Syllable(
                        range: index..<next,
                        compact: romanized,
                        initial: String(romanized.prefix(1))))
            }
            index = next
        }
        return result
    }

    private static func rangesMatching(
        query: String, syllables: [Syllable],
        token: KeyPath<Syllable, String>
    ) -> [Range<String.Index>] {
        var concat = ""
        var map: [Int] = []
        for (syllableIndex, syllable) in syllables.enumerated() {
            let piece = syllable[keyPath: token]
            guard !piece.isEmpty else { continue }
            for _ in piece {
                map.append(syllableIndex)
            }
            concat += piece
        }
        guard !concat.isEmpty, !map.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = concat.startIndex
        while searchStart < concat.endIndex,
            let match = concat.range(of: query, range: searchStart..<concat.endIndex)
        {
            let lowerOffset = concat.distance(from: concat.startIndex, to: match.lowerBound)
            let upperOffset = concat.distance(from: concat.startIndex, to: match.upperBound) - 1
            guard map.indices.contains(lowerOffset), map.indices.contains(upperOffset) else { break }
            let start = syllables[map[lowerOffset]].range.lowerBound
            let end = syllables[map[upperOffset]].range.upperBound
            ranges.append(start..<end)
            searchStart = match.upperBound
        }
        return ranges
    }

    private static func compact(_ string: String) -> String {
        string.lowercased().filter(\.isLetter)
    }

    private static func containsHan(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }
}

/// How long clipboard history is kept before pruning; raw value is the age in days persisted to UserDefaults, and `forever` is -1 so an unset key (0) falls through to the default.
enum ClipboardRetention: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365
    case forever = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return "1 Day"
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        case .year: return "1 Year"
        case .forever: return "Forever"
        }
    }

    var maxAge: TimeInterval {
        self == .forever ? .greatestFiniteMagnitude : TimeInterval(rawValue) * 86_400
    }
}

/// SQLite-backed clipboard history (rows + trigram FTS5 index in `clipboard.sqlite3`, image blobs on disk).
@MainActor
final class ClipboardStore: ObservableObject {
    /// Newest-first, pins included in place. Every pinned row remains resident however old it is.
    @Published private(set) var items: [ClipboardItem] = [] {
        didSet {
            orderedCache = nil
            revision &+= 1
        }
    }
    @Published private(set) var revision: UInt64 = 0
    private(set) var captureGeneration: UInt64 = 0
    var maxAge: TimeInterval = ClipboardRetention.threeMonths.maxAge

    /// Memoized display order, invalidated on mutation.
    private var orderedCache: [ClipboardItem]?

    private static let memoryWindow = 1000

    private static let coreSchema = """
        CREATE TABLE IF NOT EXISTS items(
          id TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          text TEXT,
          image_path TEXT,
          created_at REAL NOT NULL,
          source_app TEXT,
          pinned_at REAL,
          pinyin TEXT,
          pinyin_initials TEXT
        );
        CREATE INDEX IF NOT EXISTS items_created_at ON items(created_at);
        CREATE INDEX IF NOT EXISTS items_pinned_at
          ON items(pinned_at) WHERE pinned_at IS NOT NULL;
        """

    private static let searchSchema = """
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
          text, pinyin, pinyin_initials,
          content='items', content_rowid='rowid', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
          INSERT INTO items_fts(rowid, text, pinyin, pinyin_initials)
          VALUES(new.rowid, new.text, new.pinyin, new.pinyin_initials);
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, text, pinyin, pinyin_initials)
          VALUES('delete', old.rowid, old.text, old.pinyin, old.pinyin_initials);
        END;
        CREATE TRIGGER IF NOT EXISTS items_au
        AFTER UPDATE OF text, pinyin, pinyin_initials ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, text, pinyin, pinyin_initials)
          VALUES('delete', old.rowid, old.text, old.pinyin, old.pinyin_initials);
          INSERT INTO items_fts(rowid, text, pinyin, pinyin_initials)
          VALUES(new.rowid, new.text, new.pinyin, new.pinyin_initials);
        END;
        """

    private let imagesDir: URL
    private let dbURL: URL
    private var db: OpaquePointer?
    private var insertStmt: OpaquePointer?
    private var loadStmt: OpaquePointer?
    private var windowFloorStmt: OpaquePointer?
    private var deleteByIDStmt: OpaquePointer?
    private var pinStmt: OpaquePointer?
    private var staleImagesStmt: OpaquePointer?
    private var deleteStaleStmt: OpaquePointer?
    private var searchMetadataTask: Task<Void, Never>?

    /// Tests pass a throwaway directory so a harness run can never reach real history.
    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        dbURL = base.appendingPathComponent("clipboard.sqlite3")
        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("Could not create clipboard storage at \(base.path): \(error)")
        }
        precondition(openDatabase(), "Could not initialize clipboard database: \(databaseMessage)")
    }

    private static var defaultDirectory: URL {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            preconditionFailure("Paste requires a bundle identifier")
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    // Isolated so teardown may touch the main-actor statement/db pointers; AppCore only ever releases the store on the main actor, so no hop.
    isolated deinit {
        closeDatabase()
    }

    func load() {
        guard let stmt = loadStmt else { preconditionFailure("Clipboard database is closed") }
        sqlite3_bind_int64(stmt, 1, windowFloor())
        var loaded: [ClipboardItem] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let item = Self.row(stmt) { loaded.append(item) }
            status = sqlite3_step(stmt)
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        precondition(status == SQLITE_DONE, "Could not load clipboard history: \(databaseMessage)")
        items = loaded
        // Age passes while the app isn't running; insert-time pruning alone can't catch that.
        enforceLimits()
    }

    /// Called on load and when the retention setting changes.
    func enforceLimits() {
        prune()
    }

    /// Rowid of the oldest unpinned row the in-memory window keeps — the floor `loadStmt` reads from. 0 (no floor, load everything) when the history is shorter than the window.
    private func windowFloor() -> sqlite3_int64 {
        guard let stmt = windowFloorStmt else { return 0 }
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        sqlite3_bind_int(stmt, 1, Int32(Self.memoryWindow - 1))
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    func addText(
        _ text: String, sourceBundleID: String?, expectedGeneration: UInt64? = nil
    ) {
        if let expectedGeneration, expectedGeneration != captureGeneration { return }
        if items.first?.kind != .image, items.first?.text == text { return }
        insert(ClipboardItem(text: text, sourceBundleID: sourceBundleID))
    }

    func addImage(
        _ data: Data, sourceBundleID: String?, expectedGeneration: UInt64? = nil
    ) async {
        let generation = expectedGeneration ?? captureGeneration
        guard generation == captureGeneration else { return }
        let url = imagesDir.appendingPathComponent(UUID().uuidString + ".png")
        let item = ClipboardItem(imagePath: url.path, sourceBundleID: sourceBundleID)
        let wrote = await Task.detached(priority: .utility) {
            (try? data.write(to: url, options: .atomic)) != nil
        }.value
        guard wrote else { return }
        guard generation == captureGeneration else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        insert(item)
    }

    /// Move an item to the top of history after it is used.
    func promote(_ item: ClipboardItem) {
        // A pinned row holds its place in the Pinned section, so re-recencying one would rewrite the row and its FTS entry for no visible change.
        guard !item.isPinned, items.first?.id != item.id else { return }
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    func togglePinned(_ item: ClipboardItem) {
        if item.isPinned { unpin(item) } else { pin(item) }
    }

    func remove(_ item: ClipboardItem) {
        guard let stmt = deleteByIDStmt else { preconditionFailure("Clipboard database is closed") }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        stepAndReset(stmt, operation: "delete clipboard entry")
        items.removeAll { $0.id == item.id }
        deleteBlob(item)
    }

    func clearAll() {
        captureGeneration &+= 1
        precondition(
            sqlite3_exec(db, "DELETE FROM items", nil, nil, nil) == SQLITE_OK,
            "Could not clear clipboard history: \(databaseMessage)")
        try? FileManager.default.removeItem(at: imagesDir)
        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("Could not recreate clipboard image storage: \(error)")
        }
        items = []
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let path = item.imagePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var displayItems: [ClipboardItem] { orderedItems }

    /// Full-history search for the UI. SQLite work and resident pinyin matching both run outside the
    /// main actor; cancellation discards an obsolete keystroke's result before it reaches SwiftUI.
    func searchAsync(_ query: String) async -> [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return orderedItems }

        let resident = items
        let pinned = pinnedItems
        let path = dbURL.path
        let databaseTask = Task.detached(priority: .userInitiated) {
            () -> [ClipboardItem] in
            guard !Task.isCancelled else { return [] }
            return Self.queryDatabase(path: path, query: q)
        }
        let databaseMatches = await withTaskCancellationHandler {
            await databaseTask.value
        } onCancel: {
            databaseTask.cancel()
        }
        guard !Task.isCancelled else { return [] }

        let residentTask = Task.detached(priority: .userInitiated) {
            () -> [ClipboardItem] in
            guard !Task.isCancelled else { return [] }
            return resident.filter { $0.matches(q) }
        }
        let residentMatches = await withTaskCancellationHandler {
            await residentTask.value
        } onCancel: {
            residentTask.cancel()
        }
        guard !Task.isCancelled else { return [] }

        let residentIDs = Set(residentMatches.map(\.id))
        let pinnedMatches = pinned.filter { residentIDs.contains($0.id) }
        var seen = Set(pinnedMatches.map(\.id))
        var unpinned: [ClipboardItem] = []
        for item in databaseMatches where !item.isPinned && seen.insert(item.id).inserted {
            unpinned.append(item)
        }
        // Newly captured rows may still be waiting for their persistent pinyin metadata; merge the
        // resident window so they remain searchable immediately.
        for item in residentMatches where !item.isPinned && seen.insert(item.id).inserted {
            unpinned.append(item)
        }
        return Self.displayOrder(pinnedMatches + unpinned)
    }

    private nonisolated static func queryDatabase(path: String, query: String) -> [ClipboardItem] {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
            let connection
        else {
            sqlite3_close_v2(connection)
            preconditionFailure("Could not open clipboard database for search")
        }
        defer { sqlite3_close_v2(connection) }
        sqlite3_busy_timeout(connection, 500)

        let usesFTS = query.count >= 3
        let sql =
            usesFTS
            ? """
              SELECT i.id, i.kind, i.text, i.image_path, i.created_at, i.source_app, i.pinned_at
              FROM items_fts f JOIN items i ON i.rowid = f.rowid
              WHERE items_fts MATCH ? ORDER BY f.rowid DESC LIMIT 2000
              """
            : """
              SELECT id, kind, text, image_path, created_at, source_app, pinned_at
              FROM items
              WHERE text LIKE ? ESCAPE '\\' OR pinyin LIKE ? ESCAPE '\\'
                 OR pinyin_initials LIKE ? ESCAPE '\\'
              ORDER BY rowid DESC LIMIT 2000
              """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
            let statement
        else {
            sqlite3_finalize(statement)
            preconditionFailure("Could not prepare clipboard search")
        }
        defer { sqlite3_finalize(statement) }

        if usesFTS {
            let match = "\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            sqlite3_bind_text(statement, 1, match, -1, SQLITE_TRANSIENT)
        } else {
            let escaped = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let pattern = "%\(escaped)%"
            for index in 1...3 {
                sqlite3_bind_text(statement, Int32(index), pattern, -1, SQLITE_TRANSIENT)
            }
        }

        var results: [ClipboardItem] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if Task.isCancelled { return [] }
            if let item = row(statement) { results.append(item) }
            status = sqlite3_step(statement)
        }
        precondition(status == SQLITE_DONE, "Clipboard search failed")
        return results
    }

    private func refreshSearchMetadata(for item: ClipboardItem) async {
        guard let text = item.text, Pinyin.containsHan(text) else { return }
        let path = dbURL.path
        await Task.detached(priority: .utility) {
            Self.updateSearchMetadata(path: path, id: item.id.uuidString, text: text)
        }.value
        revision &+= 1
    }

    func waitForSearchMetadata() async {
        await searchMetadataTask?.value
    }

    private func scheduleSearchMetadataUpdate(for item: ClipboardItem) {
        guard let text = item.text, Pinyin.containsHan(text) else { return }
        let previous = searchMetadataTask
        searchMetadataTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.refreshSearchMetadata(for: item)
        }
    }

    private nonisolated static func updateSearchMetadata(path: String, id: String, text: String) {
        var connection: OpaquePointer?
        guard
            sqlite3_open_v2(path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
            let connection
        else {
            sqlite3_close_v2(connection)
            preconditionFailure("Could not open clipboard database for metadata update")
        }
        defer { sqlite3_close_v2(connection) }
        sqlite3_busy_timeout(connection, 1000)
        var update: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                connection,
                "UPDATE items SET pinyin = ?, pinyin_initials = ? WHERE id = ?", -1, &update,
                nil) == SQLITE_OK,
            let update
        else {
            sqlite3_finalize(update)
            preconditionFailure("Could not prepare clipboard metadata update")
        }
        defer { sqlite3_finalize(update) }
        let forms = Pinyin.searchForms(for: text)
        sqlite3_bind_text(update, 1, forms.full, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(update, 2, forms.initials, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(update, 3, id, -1, SQLITE_TRANSIENT)
        precondition(sqlite3_step(update) == SQLITE_DONE, "Could not update pinyin search metadata")
    }

    // MARK: - Private

    private var orderedItems: [ClipboardItem] {
        if let orderedCache { return orderedCache }
        let result = Self.displayOrder(items)
        orderedCache = result
        return result
    }

    /// One canonical order for the normal list and every search path: recent pins first, then
    /// unpinned history by copy time. Original offsets make exact timestamp ties stable.
    private nonisolated static func displayOrder(_ values: [ClipboardItem]) -> [ClipboardItem] {
        values.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element
            if left.isPinned != right.isPinned { return left.isPinned }
            if left.isPinned {
                let leftPinned = left.pinnedAt ?? .distantPast
                let rightPinned = right.pinnedAt ?? .distantPast
                if leftPinned != rightPinned { return leftPinned > rightPinned }
            }
            if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private var pinnedItems: [ClipboardItem] {
        Self.displayOrder(items.filter(\.isPinned))
    }

    /// The row gains a fresh stamp, which puts it at the head of the Pinned section.
    private func pin(_ item: ClipboardItem) {
        let stamp = Date()
        let pinned = item.with(pinnedAt: stamp)
        guard let stmt = pinStmt else { preconditionFailure("Clipboard database is closed") }
        sqlite3_bind_double(stmt, 1, stamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, SQLITE_TRANSIENT)
        stepAndReset(stmt, operation: "pin clipboard entry")
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = pinned
        } else {
            // Pinned from an FTS hit older than the in-memory window: splice it in at its recency position, since the Pinned section can only show resident rows.
            let index = items.firstIndex { $0.createdAt < pinned.createdAt } ?? items.count
            items.insert(pinned, at: index)
        }
    }

    /// Unpinning rejoins history as its newest entry so the selected row stays visible.
    private func unpin(_ item: ClipboardItem) {
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    /// Rewrite a row under the same id so it leads the history: stored order is rowid, so this is a delete + re-insert, and the fresh `createdAt` keeps the date buckets descending. The image blob is never touched.
    private func reinsert(_ updated: ClipboardItem) {
        guard let deleteStmt = deleteByIDStmt, let insertStmt else {
            preconditionFailure("Clipboard database is closed")
        }
        precondition(
            sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK,
            "Could not begin clipboard promotion: \(databaseMessage)")
        sqlite3_bind_text(deleteStmt, 1, updated.id.uuidString, -1, SQLITE_TRANSIENT)
        stepAndReset(deleteStmt, operation: "promote clipboard entry")
        bindAndInsert(insertStmt, updated)
        precondition(
            sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK,
            "Could not commit clipboard promotion: \(databaseMessage)")
        // Array ops also cover items surfaced by FTS from beyond the in-memory window.
        items.removeAll { $0.id == updated.id }
        items.insert(updated, at: 0)
        trimWindow()
        scheduleSearchMetadataUpdate(for: updated)
    }

    /// Cap the in-memory window, but never drop a pinned row: those render however old they are.
    private func trimWindow() {
        guard items.count > Self.memoryWindow, let index = items.lastIndex(where: { !$0.isPinned })
        else { return }
        items.remove(at: index)
    }

    private func insert(_ item: ClipboardItem) {
        guard let stmt = insertStmt else { preconditionFailure("Clipboard database is closed") }
        bindAndInsert(stmt, item)
        items.insert(item, at: 0)
        trimWindow()
        prune()
        scheduleSearchMetadataUpdate(for: item)
    }

    private func bindAndInsert(_ stmt: OpaquePointer, _ item: ClipboardItem) {
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, item.kind.rawValue, -1, SQLITE_TRANSIENT)
        if let text = item.text {
            sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        if let path = item.imagePath {
            sqlite3_bind_text(stmt, 4, path, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
        if let source = item.sourceBundleID {
            sqlite3_bind_text(stmt, 6, source, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        if let pinnedAt = item.pinnedAt {
            sqlite3_bind_double(stmt, 7, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        stepAndReset(stmt, operation: "save clipboard entry")
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        guard let imagesStmt = staleImagesStmt, let deleteStmt = deleteStaleStmt else {
            preconditionFailure("Clipboard database is closed")
        }
        sqlite3_bind_double(imagesStmt, 1, cutoff.timeIntervalSince1970)
        var stalePaths: [String] = []
        var status = sqlite3_step(imagesStmt)
        while status == SQLITE_ROW {
            if let path = Self.columnString(imagesStmt, 0) { stalePaths.append(path) }
            status = sqlite3_step(imagesStmt)
        }
        sqlite3_reset(imagesStmt)
        sqlite3_clear_bindings(imagesStmt)
        precondition(status == SQLITE_DONE, "Could not scan stale clipboard images")
        sqlite3_bind_double(deleteStmt, 1, cutoff.timeIntervalSince1970)
        stepAndReset(deleteStmt, operation: "prune clipboard history")
        // A retention cut can strand hundreds of files; delete them off the main actor so capture-time prune doesn't hitch.
        if !stalePaths.isEmpty {
            Task.detached(priority: .utility) {
                for path in stalePaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
        // Checked against the oldest *unpinned* row: an exempt pin sitting at the tail would otherwise make this guard permanently true and re-scan the window on every capture.
        if items.last(where: { !$0.isPinned }).map({ $0.createdAt < cutoff }) == true {
            items.removeAll { $0.createdAt < cutoff && !$0.isPinned }
        }
    }

    private func deleteBlob(_ item: ClipboardItem) {
        guard let path = item.imagePath else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(
                db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=1000;",
                nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(db, Self.coreSchema, nil, nil, nil) == SQLITE_OK
        else { return false }
        guard sqlite3_exec(db, Self.searchSchema, nil, nil, nil) == SQLITE_OK else { return false }
        insertStmt = prepare(
            """
            INSERT INTO items(id, kind, text, image_path, created_at, source_app, pinned_at)
            VALUES(?,?,?,?,?,?,?)
            """
        )
        // Every pinned row plus the newest `memoryWindow` unpinned ones, keyed off the floor rowid `windowFloor` looks up. Two indexed branches rather than one `pinned_at IS NOT NULL OR rowid >= ?`: the planner can't drive an OR from an index while holding the row order, so that form reads the whole table.
        loadStmt = prepare(
            """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at FROM (
              SELECT rowid AS rid, * FROM items WHERE rowid >= ?1
              UNION ALL
              SELECT rowid AS rid, * FROM items WHERE pinned_at IS NOT NULL AND rowid < ?1
            ) ORDER BY rid DESC
            """)
        windowFloorStmt = prepare(
            "SELECT rowid FROM items WHERE pinned_at IS NULL ORDER BY rowid DESC LIMIT 1 OFFSET ?")
        deleteByIDStmt = prepare("DELETE FROM items WHERE id = ?")
        // Only ever sets a stamp: unpinning rewrites the whole row so it leads the history again.
        pinStmt = prepare("UPDATE items SET pinned_at = ? WHERE id = ?")
        staleImagesStmt = prepare(
            """
            SELECT image_path FROM items
            WHERE created_at < ? AND pinned_at IS NULL AND image_path IS NOT NULL
            """)
        deleteStaleStmt = prepare("DELETE FROM items WHERE created_at < ? AND pinned_at IS NULL")
        return insertStmt != nil && loadStmt != nil && windowFloorStmt != nil
            && deleteByIDStmt != nil && pinStmt != nil && staleImagesStmt != nil
            && deleteStaleStmt != nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private var databaseMessage: String {
        guard let db, let message = sqlite3_errmsg(db) else { return "unknown SQLite error" }
        return String(cString: message)
    }

    private func stepAndReset(_ stmt: OpaquePointer, operation: String) {
        let status = sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        precondition(status == SQLITE_DONE, "Could not \(operation): \(databaseMessage)")
    }

    private func closeDatabase() {
        [
            insertStmt, loadStmt, windowFloorStmt, deleteByIDStmt, pinStmt,
            staleImagesStmt, deleteStaleStmt,
        ].forEach { sqlite3_finalize($0) }
        insertStmt = nil
        loadStmt = nil
        windowFloorStmt = nil
        deleteByIDStmt = nil
        pinStmt = nil
        staleImagesStmt = nil
        deleteStaleStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    private nonisolated static func row(_ stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let kindString = columnString(stmt, 1),
            let storedKind = ClipboardItem.Kind(rawValue: kindString)
        else { return nil }
        return ClipboardItem(
            id: id, kind: storedKind, text: columnString(stmt, 2), imagePath: columnString(stmt, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            sourceBundleID: columnString(stmt, 5), pinnedAt: columnDate(stmt, 6))
    }

    private nonisolated static func columnDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    private nonisolated static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}

/// Conservative classification for clipboard text. Whole-string http(s) URLs classify as links;
/// strong syntax forms classify as code on their own; weaker punctuation signals must combine,
/// keeping prose and ordinary messages as text. Only a bounded prefix is inspected for code so a
/// large copy cannot stall capture.
enum ClipboardTextClassifier {
    private static let sampleLimit = 12_000

    static func kind(for text: String) -> ClipboardItem.Kind {
        if isLink(text) { return .link }
        return isCode(text) ? .code : .text
    }

    /// Whole clipboard string is a single http(s) URL (no surrounding prose).
    private static func isLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return false }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", url.host != nil
        else { return false }
        return true
    }

    private static func isCode(_ text: String) -> Bool {
        let sample = String(text.prefix(sampleLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.count >= 4 else { return false }

        if sample.hasPrefix("```") || sample.hasPrefix("#!") { return true }
        if isJSONObject(sample) { return true }

        let strongSyntax = #"(?m)^\s*(?:(?:import\s+.+(?:\s+from\s+)?[\"'<])|(?:export\s+(?:default\s+)?)|(?:(?:const|let|var)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*(?::[^=\n]+)?=)|(?:(?:func|function|def|class|struct|enum|protocol|extension|interface|type|fn)\s+[A-Za-z_][A-Za-z0-9_]*)|(?:(?:public|private|protected|internal|open|static|final|pub)\s+(?:class|struct|enum|func|fn|let|var|const)\b)|(?:#include\s*[<\"])|(?:(?:SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER)\b.+\b(?:FROM|INTO|TABLE|SET)\b))"#
        if matches(strongSyntax, in: sample) { return true }

        let standaloneCall = #"^\s*[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*\s*\([^\n]*\)\s*;?\s*$"#
        if matches(standaloneCall, in: sample) { return true }

        let markup = #"(?s)<[A-Za-z][^>]*>.*</[A-Za-z][^>]*>"#
        if matches(markup, in: sample) { return true }

        var score = 0
        if sample.contains("{") && sample.contains("}") { score += 1 }
        if sample.contains("=>") || sample.contains("::") || sample.contains("?.") { score += 1 }
        if matches(#"(?m);\s*$"#, in: sample) { score += 1 }
        if matches(#"\b(?:return|await|throw|guard|switch|case|while|foreach|impl|lambda)\b"#, in: sample) {
            score += 1
        }
        if matches(#"(?m)^\s{2,}\S+"#, in: sample) && sample.contains("\n") { score += 1 }
        if matches(#"\b[A-Za-z_$][A-Za-z0-9_$]*\s*\([^\n)]*\)"#, in: sample) {
            score += 1
        }
        return score >= 3
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isJSONObject(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[", let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return false }
        return object is [String: Any] || object is [Any]
    }
}
