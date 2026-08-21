import XCTest

/// Controller IPC wire format and unix-socket transport, exercised over a real loopback socket.
final class IPCTests: XCTestCase {
    // MARK: - Wire format

    func testEncodeDecodeRoundtrip() throws {
        let original: [String: Any] = [
            "cmd": "items.search",
            "args": ["query": "hello", "limit": 20],
        ]
        let data = try PasteControllerIPC.encode(original)
        let decoded = try PasteControllerIPC.decode(data)

        XCTAssertEqual(decoded["cmd"] as? String, "items.search")
        let args = try XCTUnwrap(decoded["args"] as? [String: Any])
        XCTAssertEqual(args["query"] as? String, "hello")
        XCTAssertEqual(args["limit"] as? Int, 20)
    }

    func testDecodeRejectsNonDictionaryPayload() {
        let data = Data("[1, 2, 3]".utf8)
        XCTAssertThrowsError(try PasteControllerIPC.decode(data))
    }

    func testDecodeRejectsGarbage() {
        XCTAssertThrowsError(try PasteControllerIPC.decode(Data([0xFF, 0xFE])))
    }

    func testResponseShape() throws {
        let ok = PasteControllerIPC.response(ok: true, data: ["count": 3])
        XCTAssertEqual(ok["v"] as? Int, PasteControllerIPC.protocolVersion)
        XCTAssertEqual(ok["ok"] as? Bool, true)
        XCTAssertEqual((ok["data"] as? [String: Any])?["count"] as? Int, 3)
        XCTAssertNil(ok["error"])

        let failure = PasteControllerIPC.response(ok: false, error: "boom")
        XCTAssertEqual(failure["ok"] as? Bool, false)
        XCTAssertEqual(failure["error"] as? String, "boom")
        XCTAssertNil(failure["data"])
    }

    func testSocketPathPointsAtApplicationSupport() {
        let path = PasteControllerIPC.socketPath
        XCTAssertTrue(
            path.hasSuffix("Library/Application Support/com.eli.Paste/controller.sock"),
            "Unexpected socket path: \(path)")
    }

    // MARK: - Transport

    /// Unix sockets are limited to `sun_path` (104 bytes on macOS), and the default per-process
    /// temp directory under /var/folders is too deep. Use a short fixed-prefix path in /tmp.
    private func makeSocketPath(_ label: String) -> URL {
        URL(fileURLWithPath: "/tmp/paste-tests-\(label)-\(UUID().uuidString.prefix(6)).sock")
    }

    private func removeSocket(_ path: URL) {
        try? FileManager.default.removeItem(at: path)
    }

    func testListenMarksSocketOwnerOnly() throws {
        let path = makeSocketPath("socket-perms")
        defer { removeSocket(path) }

        let fd = try PasteControllerTransport.listen(at: path.path)
        defer {
            Darwin.close(fd)
            try? FileManager.default.removeItem(at: path)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.uint16Value, 0o600)
    }

    func testListenRejectsOverlongPaths() throws {
        let longPath = TestSupport.makeTemporaryDirectory("socket-long")
            .appendingPathComponent(String(repeating: "a", count: 80)).path
        XCTAssertThrowsError(try PasteControllerTransport.listen(at: longPath)) { error in
            guard case PasteControllerTransport.TransportError.pathTooLong = error else {
                return XCTFail("Expected pathTooLong, got \(error)")
            }
        }
    }

    func testMessageEchoRoundtrip() throws {
        let path = makeSocketPath("socket-echo")
        defer { removeSocket(path) }

        let listenFD = try PasteControllerTransport.listen(at: path.path)

        // One-shot echo server: accept a single client, read one message, write it back.
        let server = DispatchQueue.global(qos: .userInitiated)
        let served = XCTestExpectation(description: "server handled one message")
        server.async {
            guard let client = PasteControllerTransport.accept(listenFD) else {
                served.fulfill()
                return
            }
            defer { Darwin.close(client) }
            if let message = try? PasteControllerTransport.readMessage(from: client) {
                try? PasteControllerTransport.writeMessage(message, to: client)
            }
            served.fulfill()
        }

        let payload = try PasteControllerIPC.encode(["cmd": "status"])
        let clientFD = try PasteControllerTransport.connect(path: path.path, timeout: 5)
        defer { Darwin.close(clientFD) }

        try PasteControllerTransport.writeMessage(payload, to: clientFD)
        let reply = try PasteControllerTransport.readMessage(from: clientFD)
        XCTAssertEqual(reply, payload)

        wait(for: [served], timeout: 5)
        Darwin.close(listenFD)
        try? FileManager.default.removeItem(at: path)
    }

    func testLargeMessageEchoRoundtrip() throws {
        let path = makeSocketPath("socket-large")
        defer { removeSocket(path) }

        let listenFD = try PasteControllerTransport.listen(at: path.path)
        let server = DispatchQueue.global(qos: .userInitiated)
        let served = XCTestExpectation(description: "server echoed large message")
        server.async {
            guard let client = PasteControllerTransport.accept(listenFD) else {
                served.fulfill()
                return
            }
            defer { Darwin.close(client) }
            if let message = try? PasteControllerTransport.readMessage(from: client) {
                try? PasteControllerTransport.writeMessage(message, to: client)
            }
            served.fulfill()
        }

        // Large enough to span multiple 4 KiB reads and potentially partial writes.
        let largePayload = Data(String(repeating: "x", count: 256 * 1024).utf8)
        let clientFD = try PasteControllerTransport.connect(path: path.path, timeout: 10)
        defer { Darwin.close(clientFD) }

        try PasteControllerTransport.writeMessage(largePayload, to: clientFD)
        let reply = try PasteControllerTransport.readMessage(from: clientFD)
        XCTAssertEqual(reply, largePayload)

        wait(for: [served], timeout: 10)
        Darwin.close(listenFD)
        try? FileManager.default.removeItem(at: path)
    }

    func testReadOnFreshlyClosedConnectionThrowsClosed() throws {
        let path = makeSocketPath("socket-closed")
        defer { removeSocket(path) }

        let listenFD = try PasteControllerTransport.listen(at: path.path)
        defer {
            Darwin.close(listenFD)
            try? FileManager.default.removeItem(at: path)
        }

        // The server accepts and immediately closes, so the next client read hits EOF.
        let server = DispatchQueue.global(qos: .userInitiated)
        let served = XCTestExpectation(description: "server accepted and closed")
        server.async {
            if let client = PasteControllerTransport.accept(listenFD) {
                Darwin.close(client)
            }
            served.fulfill()
        }

        let clientFD = try PasteControllerTransport.connect(path: path.path, timeout: 5)
        defer { Darwin.close(clientFD) }

        wait(for: [served], timeout: 5)
        XCTAssertThrowsError(try PasteControllerTransport.readMessage(from: clientFD)) { error in
            guard case PasteControllerTransport.TransportError.closed = error else {
                return XCTFail("Expected closed, got \(error)")
            }
        }
    }
}
