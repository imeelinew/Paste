import Darwin
import Foundation

enum PasteCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch let error as UsageError {
            fputs("\(error.message)\n", stderr)
            if error.showHelp { fputs("\n\(helpText)\n", stderr) }
            exit(error.showHelp ? 1 : 1)
        } catch let error as CommandError {
            fputs("\(error.message)\n", stderr)
            exit(2)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(2)
        }
    }

    private static func run(_ arguments: [String]) throws {
        var json = false
        var rest: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--json" || argument == "--raw" {
                json = true
            } else if argument == "-h" || argument == "--help" {
                print(helpText)
                return
            } else if argument.hasPrefix("-") {
                throw UsageError("Unknown option: \(argument)", showHelp: true)
            } else {
                rest.append(contentsOf: arguments[index...])
                break
            }
            index += 1
        }

        guard let head = rest.first else {
            print(helpText)
            return
        }
        if head == "help" {
            print(helpText)
            return
        }

        let command = try parseCommand(rest)
        let response = try send(command)
        let ok = response["ok"] as? Bool ?? false
        if json {
            printJSON(response)
            if !ok { exit(2) }
            return
        }
        if !ok {
            throw CommandError(response["error"] as? String ?? "Request failed")
        }
        printHuman(command: command.cmd, data: response["data"])
    }

    private static func parseCommand(_ rest: [String]) throws -> (cmd: String, args: [String: String]) {
        let name = rest[0].lowercased()
        let tail = Array(rest.dropFirst())
        switch name {
        case "version":
            return ("version", [:])
        case "status":
            return ("status", [:])
        case "items":
            return try parseItems(tail)
        case "cards":
            return try parseCards(tail)
        default:
            throw UsageError("Unknown command: \(rest[0])", showHelp: true)
        }
    }

    private static func parseItems(_ tail: [String]) throws -> (cmd: String, args: [String: String]) {
        guard let action = tail.first?.lowercased() else {
            throw UsageError("Usage: paste-cli items <list|search|get|add|rename|pin|unpin|delete|copy|reveal>", showHelp: false)
        }
        let args = Array(tail.dropFirst())
        switch action {
        case "list":
            return ("items.list", [:])
        case "search":
            let query = args.joined(separator: " ")
            return ("items.search", ["query": query])
        case "get", "pin", "unpin", "delete", "copy", "reveal":
            guard let id = args.first else { throw UsageError("Usage: paste-cli items \(action) <id>") }
            return ("items.\(action)", ["id": id])
        case "rename":
            guard args.count >= 2 else { throw UsageError("Usage: paste-cli items rename <id> <title>") }
            return ("items.rename", ["id": args[0], "title": args.dropFirst().joined(separator: " ")])
        case "add":
            let text = try parseAddText(args)
            return ("items.add", ["text": text])
        default:
            throw UsageError("Unknown items command: \(action)")
        }
    }

    private static func parseAddText(_ args: [String]) throws -> String {
        var text: String?
        var positional: [String] = []
        var index = 0
        while index < args.count {
            let argument = args[index]
            if argument == "--text" {
                let next = index + 1
                guard next < args.count else { throw UsageError("Usage: paste-cli items add --text <text>") }
                text = args[next]
                index += 2
                continue
            }
            positional.append(argument)
            index += 1
        }
        let value = text ?? positional.joined(separator: " ")
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageError("Usage: paste-cli items add --text <text>")
        }
        return value
    }

    private static func parseCards(_ tail: [String]) throws -> (cmd: String, args: [String: String]) {
        guard let action = tail.first?.lowercased() else {
            throw UsageError("Usage: paste-cli cards <list|show|close|close-all|park|unpark>")
        }
        let args = Array(tail.dropFirst())
        switch action {
        case "list":
            return ("cards.list", [:])
        case "show", "close":
            guard let id = args.first else { throw UsageError("Usage: paste-cli cards \(action) <id>") }
            return ("cards.\(action)", ["id": id])
        case "close-all":
            return ("cards.close-all", [:])
        case "park":
            return ("cards.park", [:])
        case "unpark":
            return ("cards.unpark", [:])
        default:
            throw UsageError("Unknown cards command: \(action)")
        }
    }

    private static func send(_ command: (cmd: String, args: [String: String])) throws -> [String: Any] {
        let fd: Int32
        do {
            fd = try PasteControllerTransport.connect(
                path: PasteControllerIPC.socketPath, timeout: 8)
        } catch {
            throw CommandError("Paste is not running (\(error.localizedDescription))")
        }
        defer { Darwin.close(fd) }

        let payload: [String: Any] = [
            "v": PasteControllerIPC.protocolVersion,
            "cmd": command.cmd,
            "args": command.args,
        ]
        try PasteControllerTransport.writeMessage(try PasteControllerIPC.encode(payload), to: fd)
        let data = try PasteControllerTransport.readMessage(from: fd)
        return try PasteControllerIPC.decode(data)
    }

    private static func printJSON(_ object: Any) {
        guard JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            print("{\"ok\":false,\"error\":\"Failed to encode JSON\"}")
            return
        }
        print(text)
    }

    private static func printHuman(command: String, data: Any?) {
        switch command {
        case "version":
            let payload = data as? [String: Any] ?? [:]
            print(
                "Paste \(payload["version"] as? String ?? "") (\(payload["build"] as? String ?? "")) protocol \(jsonInt(payload["controller-protocol"]))"
            )
        case "status":
            let payload = data as? [String: Any] ?? [:]
            let parked = payload["parked"] as? Bool == true ? " parked" : ""
            print(
                "running  items=\(jsonInt(payload["items"]))  cards=\(jsonInt(payload["cards"]))\(parked)"
            )
        case "items.list", "items.search":
            printItems((data as? [String: Any])?["items"] as? [Any] ?? [])
        case "items.get", "items.add", "items.rename", "items.pin", "items.unpin":
            printItem(data as? [String: Any] ?? [:], full: command == "items.get" || command == "items.add")
        case "items.delete", "items.copy", "items.reveal", "cards.show", "cards.close":
            if let id = (data as? [String: Any])?["id"] as? String {
                print(id)
            }
        case "cards.list":
            let payload = data as? [String: Any] ?? [:]
            if payload["parked"] as? Bool == true { print("parked") }
            printCards(payload["cards"] as? [Any] ?? [])
        case "cards.close-all":
            print("closed \(jsonInt((data as? [String: Any])?["count"]))")
        case "cards.park":
            print("parked")
        case "cards.unpark":
            print("unparked")
        default:
            if let data { printJSON(data) }
        }
    }

    private static func printItems(_ items: [Any]) {
        if items.isEmpty {
            print("(none)")
            return
        }
        for entry in items {
            guard let item = entry as? [String: Any] else { continue }
            let pin = item["pinned"] as? Bool == true ? "*" : " "
            let kind = (item["kind"] as? String ?? "").padding(toLength: 5, withPad: " ", startingAt: 0)
            let title = item["title"] as? String ?? ""
            print("\(item["id"] as? String ?? "")  \(kind)\(pin)  \(title)")
        }
    }

    private static func printItem(_ item: [String: Any], full: Bool) {
        print("id       \(item["id"] as? String ?? "")")
        print("kind     \(item["kind"] as? String ?? "")")
        print("title    \(item["title"] as? String ?? "")")
        print("pinned   \(item["pinned"] as? Bool == true)")
        if full, let text = item["text"] as? String {
            print("text")
            print(text)
        }
    }

    private static func printCards(_ cards: [Any]) {
        if cards.isEmpty {
            print("(none)")
            return
        }
        for entry in cards {
            guard let card = entry as? [String: Any] else { continue }
            var flags: [String] = []
            if card["visible"] as? Bool == true { flags.append("visible") }
            if card["parked"] as? Bool == true { flags.append("parked") }
            let mark = flags.isEmpty ? "" : "  \(flags.joined(separator: ","))"
            print(
                "\(card["id"] as? String ?? "")  \((card["kind"] as? String ?? "").padding(toLength: 8, withPad: " ", startingAt: 0))  \(card["title"] as? String ?? "")\(mark)"
            )
        }
    }

    private static let helpText = """
        Paste CLI
        Usage: paste-cli [--json] <command> [arguments]

        Command groups:
          Status    version, status
          Items     items list, search, get, add, rename, pin, unpin, delete, copy, reveal
          Cards     cards list, show, close, close-all, park, unpark

        Use `help` for this message.

        Available parameters:
          --json / --raw  Output JSON instead of the human-readable format
        """

    private static func jsonInt(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? (value as? Int) ?? 0
    }
}

private struct UsageError: Error {
    let message: String
    var showHelp = false
    init(_ message: String, showHelp: Bool = false) {
        self.message = message
        self.showHelp = showHelp
    }
}

private struct CommandError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

PasteCLI.main()
