// Standalone test for the real clipboard store:
// swiftc -swift-version 6 Paste/Core/ClipboardStore.swift Tools/clipboard-test.swift -o /tmp/clipboard-test && /tmp/clipboard-test
//
// Every store uses a fresh temporary directory and can never touch real clipboard history.

import Foundation

@main
@MainActor
struct ClipboardTests {
    static var failures = 0
    static var passes = 0

    static func main() async {
        pinOrder()
        unpinRejoinsAsNewest()
        pasteLeavesPinsAlone()
        pinsSurvivePruningAndMemoryWindow()
        persistenceAndClear()
        currentSchema()
        codeClassification()
        await imageLifecycle()
        await pinsLeadSearches()
        await fullHistoryShortAndPinyinSearch()
        await clearInvalidatesPendingCaptures()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Ordering and retention

    static func pinOrder() {
        withStore { store, _ in
            store.addText("oldest", sourceBundleID: nil)
            store.addText("middle", sourceBundleID: nil)
            store.addText("newest", sourceBundleID: nil)

            store.togglePinned(item(store, "oldest"))
            expect(texts(store) == ["oldest", "newest", "middle"], "first pin leads")

            store.togglePinned(item(store, "middle"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "later pins join below earlier pins")

            store.togglePinned(item(store, "newest"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "pin order is independent of history recency")
        }
    }

    static func unpinRejoinsAsNewest() {
        withStore { store, _ in
            store.addText("a", sourceBundleID: nil)
            store.addText("b", sourceBundleID: nil)
            store.addText("c", sourceBundleID: nil)
            let before = item(store, "a").createdAt

            store.togglePinned(item(store, "a"))
            store.togglePinned(item(store, "a"))

            expect(texts(store) == ["a", "c", "b"], "unpin promotes into history")
            expect(!item(store, "a").isPinned, "unpin clears its stamp")
            expect(item(store, "a").createdAt > before, "unpin refreshes recency")
        }
    }

    static func pasteLeavesPinsAlone() {
        withStore { store, _ in
            store.addText("one", sourceBundleID: nil)
            store.addText("two", sourceBundleID: nil)
            store.togglePinned(item(store, "one"))
            store.togglePinned(item(store, "two"))
            let stamp = item(store, "one").createdAt

            store.promote(item(store, "one"))

            expect(texts(store) == ["one", "two"], "promote leaves pins in place")
            expect(item(store, "one").createdAt == stamp, "promote does not rewrite a pin")

            store.addText("three", sourceBundleID: nil)
            store.addText("four", sourceBundleID: nil)
            store.promote(item(store, "three"))
            expect(
                texts(store) == ["one", "two", "three", "four"],
                "promote moves an unpinned row to the history head")
        }
    }

    static func pinsSurvivePruningAndMemoryWindow() {
        withStore { store, dir in
            store.addText("persistent pin", sourceBundleID: nil)
            store.togglePinned(item(store, "persistent pin"))
            for index in 0..<1_050 {
                store.addText("filler \(index)", sourceBundleID: nil)
            }
            expect(
                store.items.first(where: { $0.text == "persistent pin" })?.isPinned == true,
                "a pin stays resident beyond the memory window")

            store.maxAge = -1
            store.enforceLimits()
            expect(texts(store) == ["persistent pin"], "retention removes only unpinned rows")

            let reopened = ClipboardStore(directory: dir)
            reopened.load()
            expect(texts(reopened) == ["persistent pin"], "a retained pin survives relaunch")
        }
    }

    // MARK: - Persistence and schema

    static func persistenceAndClear() {
        withStore { store, dir in
            store.addText("first", sourceBundleID: "com.example.Source")
            store.addText("second", sourceBundleID: nil)
            store.addText("third", sourceBundleID: nil)
            store.togglePinned(item(store, "third"))
            store.togglePinned(item(store, "first"))

            let reopened = ClipboardStore(directory: dir)
            reopened.load()
            expect(
                texts(reopened) == ["third", "first", "second"],
                "rows, source metadata, and pin order persist")
            expect(
                item(reopened, "first").sourceBundleID == "com.example.Source",
                "source application persists")

            reopened.clearAll()
            expect(reopened.items.isEmpty, "clear removes all rows")
            let empty = ClipboardStore(directory: dir)
            empty.load()
            expect(empty.items.isEmpty, "clear persists across relaunch")
        }
    }

    static func currentSchema() {
        withStore { _, dir in
            let database = dir.appendingPathComponent("clipboard.sqlite3")
            expect(
                sqlite(database, "SELECT name FROM pragma_table_info('items')")
                    == [
                        "id", "kind", "text", "image_path", "created_at", "source_app",
                        "pinned_at", "pinyin", "pinyin_initials",
                    ],
                "fresh databases use exactly the current columns")
            expect(
                Set(sqlite(database, "SELECT name FROM sqlite_master WHERE type = 'trigger'"))
                    == ["items_ai", "items_ad", "items_au"],
                "fresh databases install the current FTS triggers")
        }
    }

    static func codeClassification() {
        withStore { store, _ in
            store.addText("let answer = 42", sourceBundleID: nil)
            expect(store.items.first?.kind == .code, "declarations classify as code")

            store.addText("{\"enabled\": true, \"count\": 3}", sourceBundleID: nil)
            expect(store.items.first?.kind == .code, "JSON classifies as code")

            store.addText("Paste keeps your clipboard history close at hand.", sourceBundleID: nil)
            expect(store.items.first?.kind == .text, "ordinary prose remains text")

            store.addText("https://example.com/path?q=value", sourceBundleID: nil)
            expect(store.items.first?.kind == .text, "URLs remain text")
        }
    }

    static func imageLifecycle() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir)
        let fixture = Data([0x89, 0x50, 0x4E, 0x47])

        await store.addImage(fixture, sourceBundleID: nil)

        guard let image = store.items.first, let path = image.imagePath else {
            fail("image capture creates a row")
            return
        }
        expect(FileManager.default.fileExists(atPath: path), "image capture owns its blob")
        store.remove(image)
        expect(!FileManager.default.fileExists(atPath: path), "removing a row removes its blob")
    }

    // MARK: - Search and capture races

    static func pinsLeadSearches() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir)
        store.addText("needle in the haystack", sourceBundleID: nil)
        store.togglePinned(item(store, "needle in the haystack"))
        for index in 0..<260 {
            store.addText("haystack filler \(index)", sourceBundleID: nil)
        }

        let long = await store.searchAsync("haystack")
        expect(long.first?.text == "needle in the haystack", "pins lead literal search")
        expect(long.filter(\.isPinned).count == 1, "a pinned search hit is unique")

        let short = await store.searchAsync("ne")
        expect(short.first?.text == "needle in the haystack", "pins lead short search")
    }

    static func fullHistoryShortAndPinyinSearch() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir)
        store.addText("xy archived literal", sourceBundleID: nil)
        store.addText("你好归档", sourceBundleID: nil)
        for index in 0..<1_100 {
            store.addText("ordinary filler \(index)", sourceBundleID: nil)
        }
        await store.waitForSearchMetadata()

        expect(
            !store.items.contains { $0.text == "xy archived literal" },
            "search fixtures fall beyond the resident window")
        let short = await store.searchAsync("xy")
        expect(short.first?.text == "xy archived literal", "short queries search durable history")
        let fullPinyin = await store.searchAsync("nihaoguidang")
        expect(fullPinyin.first?.text == "你好归档", "full pinyin searches durable history")
        let initials = await store.searchAsync("nhgd")
        expect(initials.first?.text == "你好归档", "pinyin initials search durable history")
    }

    static func clearInvalidatesPendingCaptures() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir)
        let oldGeneration = store.captureGeneration
        let fixture = Data(repeating: 0x5A, count: 16 * 1_024 * 1_024)
        let pendingImage = Task { @MainActor in
            await store.addImage(fixture, sourceBundleID: nil, expectedGeneration: oldGeneration)
        }
        await Task.yield()
        store.clearAll()
        await pendingImage.value
        store.addText("stale text", sourceBundleID: nil, expectedGeneration: oldGeneration)

        expect(store.items.isEmpty, "captures observed before clear cannot reappear")
        let imageFiles =
            (try? FileManager.default.contentsOfDirectory(
                at: dir.appendingPathComponent("images"), includingPropertiesForKeys: nil)) ?? []
        expect(imageFiles.isEmpty, "a stale completed image write cleans itself up")
    }

    // MARK: - Harness

    static func withStore(_ body: (ClipboardStore, URL) -> Void) {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        body(ClipboardStore(directory: dir), dir)
    }

    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("paste-clipboard-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func sqlite(_ database: URL, _ sql: String) -> [String] {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [database.path, sql]
        task.standardOutput = pipe
        try! task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        precondition(task.terminationStatus == 0, "sqlite3 failed")
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    static func texts(_ store: ClipboardStore) -> [String] {
        store.displayItems.compactMap(\.text)
    }

    static func item(_ store: ClipboardStore, _ text: String) -> ClipboardItem {
        guard let match = store.items.first(where: { $0.text == text }) else {
            preconditionFailure("No clipboard entry named \(text)")
        }
        return match
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        if condition() {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
