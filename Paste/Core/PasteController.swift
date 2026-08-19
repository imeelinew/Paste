import AppKit
import Darwin
import Foundation

/// In-process command server. paste-cli is a thin client over the unix socket this binds.
@MainActor
final class PasteController {
    private unowned let core: AppCore
    private let cards: PinnedImageWindowController
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let acceptQueue = DispatchQueue(label: "com.eli.Paste.controller")

    init(core: AppCore, cards: PinnedImageWindowController) {
        self.core = core
        self.cards = cards
    }

    func start() {
        signal(SIGPIPE, SIG_IGN)
        stop()
        do {
            let fd = try PasteControllerTransport.listen(at: PasteControllerIPC.socketPath)
            listenFD = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
            let onAccept: @Sendable () -> Void = {
                Self.serveAcceptedClient(from: fd)
            }
            let onCancel: @Sendable () -> Void = {
                Darwin.close(fd)
            }
            source.setEventHandler(handler: onAccept)
            source.setCancelHandler(handler: onCancel)
            source.resume()
            acceptSource = source
        } catch {
            listenFD = -1
        }
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        _ = unlink(PasteControllerIPC.socketPath)
    }

    private nonisolated static func serveAcceptedClient(from listenFD: Int32) {
        guard let client = PasteControllerTransport.accept(listenFD) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let requestData: Data
            do {
                requestData = try PasteControllerTransport.readMessage(from: client)
            } catch {
                Darwin.close(client)
                return
            }
            Task { @MainActor in
                let response = await AppCore.shared.handleControllerRequest(requestData)
                let data = try? PasteControllerIPC.encode(response)
                DispatchQueue.global(qos: .userInitiated).async {
                    if let data {
                        try? PasteControllerTransport.writeMessage(data, to: client)
                    }
                    Darwin.close(client)
                }
            }
        }
    }

    func handleRequest(_ requestData: Data) async -> [String: Any] {
        let request: [String: Any]
        do {
            request = try PasteControllerIPC.decode(requestData)
        } catch {
            return PasteControllerIPC.response(ok: false, error: "Invalid JSON")
        }
        let command = (request["cmd"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let args = request["args"] as? [String: Any] ?? [:]
        do {
            let data = try await execute(command, args: args)
            return PasteControllerIPC.response(ok: true, data: data)
        } catch let error as ControllerError {
            return PasteControllerIPC.response(ok: false, error: error.message)
        } catch {
            return PasteControllerIPC.response(ok: false, error: error.localizedDescription)
        }
    }

    private func execute(_ command: String, args: [String: Any]) async throws -> Any {
        switch command {
        case "version":
            return versionPayload()
        case "status":
            return statusPayload()
        case "items.list":
            return ["items": core.clipboardStore.displayItems.map { itemJSON($0, preview: true) }]
        case "items.search":
            let query = stringArg(args, "query")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let items =
                query.isEmpty
                ? core.clipboardStore.displayItems
                : await core.clipboardStore.searchAsync(query)
            return ["items": items.map { itemJSON($0, preview: true) }]
        case "items.get":
            return itemJSON(try requireItem(args), preview: false)
        case "items.add":
            let text = stringArg(args, "text")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { throw ControllerError("Text is empty") }
            guard let item = core.clipboardStore.addText(text, sourceBundleID: "com.eli.Paste.cli")
            else {
                throw ControllerError("Failed to add item")
            }
            return itemJSON(item, preview: false)
        case "items.rename":
            let item = try requireItem(args)
            let title = stringArg(args, "title") ?? ""
            core.clipboardStore.setCustomTitle(title, for: item.id)
            return itemJSON(try requireItem(id: item.id), preview: false)
        case "items.pin":
            let item = try requireItem(args)
            if !item.isPinned { core.clipboardStore.togglePinned(item) }
            return itemJSON(try requireItem(id: item.id), preview: true)
        case "items.unpin":
            let item = try requireItem(args)
            if item.isPinned { core.clipboardStore.togglePinned(item) }
            return itemJSON(try requireItem(id: item.id), preview: true)
        case "items.delete":
            let item = try requireItem(args)
            core.clipboardStore.remove(item)
            return ["id": item.id.uuidString]
        case "items.copy":
            let item = try requireItem(args)
            let copied = await Paster.copy(item, store: core.clipboardStore, willWrite: {})
            guard copied else { throw ControllerError("Failed to copy item") }
            return ["id": item.id.uuidString]
        case "items.reveal":
            let item = try requireItem(args)
            guard item.kind == .image else { throw ControllerError("Not an image") }
            guard core.clipboardStore.imageURL(for: item) != nil else {
                throw ControllerError("Image file is missing")
            }
            core.revealClipboardImage(item, dismissPalette: false)
            return ["id": item.id.uuidString]
        case "cards.list":
            return ["cards": cards.cardInfos().map(cardJSON), "parked": cards.areParked]
        case "cards.show":
            let item = try requireItem(args)
            switch item.kind {
            case .image:
                guard core.clipboardStore.imageURL(for: item) != nil else {
                    throw ControllerError("Image file is missing")
                }
            case .text, .code, .link:
                guard let text = item.text, !text.isEmpty else {
                    throw ControllerError("Item has no text")
                }
            }
            core.pinToScreen(item, dismissPalette: false)
            return ["id": item.id.uuidString]
        case "cards.close":
            let id = try requireID(args)
            guard cards.closeCard(id) else { throw ControllerError("Card not found") }
            return ["id": id.uuidString]
        case "cards.close-all":
            let count = cards.closeAllCards()
            return ["count": count]
        case "cards.park":
            cards.parkCards()
            return ["parked": true]
        case "cards.unpark":
            cards.unparkCards()
            return ["parked": false]
        default:
            throw ControllerError("Unknown command: \(command)")
        }
    }

    private func versionPayload() -> [String: Any] {
        let bundle = Bundle.main
        return [
            "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "",
            "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "controller-protocol": PasteControllerIPC.protocolVersion,
        ]
    }

    private func statusPayload() -> [String: Any] {
        [
            "running": true,
            "items": core.clipboardStore.displayItems.count,
            "cards": cards.cardInfos().count,
            "parked": cards.areParked,
            "controller-protocol": PasteControllerIPC.protocolVersion,
        ]
    }

    private func itemJSON(_ item: ClipboardItem, preview: Bool) -> [String: Any] {
        var payload: [String: Any] = [
            "id": item.id.uuidString,
            "kind": item.kind.rawValue,
            "title": item.displayTitle(locale: core.settings.language.locale),
            "pinned": item.isPinned,
            "createdAt": item.createdAt.timeIntervalSince1970,
        ]
        if let source = item.sourceBundleID {
            payload["sourceBundleID"] = source
        }
        if let text = item.text {
            if preview, text.count > 240 {
                payload["text"] = String(text.prefix(240))
                payload["truncated"] = true
            } else {
                payload["text"] = text
            }
        }
        if item.kind == .image {
            payload["hasImage"] = true
        }
        return payload
    }

    private func cardJSON(_ card: PinnedCardInfo) -> [String: Any] {
        [
            "id": card.id.uuidString,
            "kind": card.kind,
            "title": card.title,
            "visible": card.visible,
            "parked": card.parked,
        ]
    }

    private func requireItem(_ args: [String: Any]) throws -> ClipboardItem {
        try requireItem(id: try requireID(args))
    }

    private func requireItem(id: UUID) throws -> ClipboardItem {
        guard let item = core.clipboardStore.item(id: id) else {
            throw ControllerError("Item not found")
        }
        return item
    }

    private func requireID(_ args: [String: Any]) throws -> UUID {
        guard let raw = stringArg(args, "id"), let id = UUID(uuidString: raw) else {
            throw ControllerError("Missing or invalid id")
        }
        return id
    }

    private func stringArg(_ args: [String: Any], _ key: String) -> String? {
        if let value = args[key] as? String { return value }
        if let value = args[key] as? NSNumber { return value.stringValue }
        return nil
    }
}

private struct ControllerError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
