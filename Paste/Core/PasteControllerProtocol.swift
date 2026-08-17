import Darwin
import Foundation

/// Wire format shared by Paste.app (server) and paste-cli (client).
/// One JSON object per connection, newline-terminated. The live app owns all state.
enum PasteControllerIPC {
    static let protocolVersion = 1
    static let appBundleID = "com.eli.Paste"
    static let maxMessageBytes = 8 * 1024 * 1024

    static var socketPath: String {
        // Prefer $HOME so paste-cli inside an agent sandbox still hits the real
        // Application Support directory the GUI app binds. FileManager's
        // search path can be redirected in that environment.
        let home =
            ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appBundleID, isDirectory: true)
            .appendingPathComponent("controller.sock")
            .path
    }

    static func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw POSIXError(.EBADMSG)
        }
        return dictionary
    }

    static func response(ok: Bool, error: String? = nil, data: Any? = nil) -> [String: Any] {
        var payload: [String: Any] = [
            "v": protocolVersion,
            "ok": ok,
        ]
        if let error { payload["error"] = error }
        if let data { payload["data"] = data }
        return payload
    }
}

enum PasteControllerTransport {
    enum TransportError: Error, LocalizedError {
        case pathTooLong
        case socket(Int32)
        case notRunning
        case timeout
        case closed
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .pathTooLong: "Controller socket path is too long"
            case .socket(let code): "Socket error \(code)"
            case .notRunning: "Paste is not running"
            case .timeout: "Timed out waiting for Paste"
            case .closed: "Controller connection closed"
            case .tooLarge: "Controller message is too large"
            }
        }
    }

    static func listen(at path: String) throws -> Int32 {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        _ = unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TransportError.socket(errno) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        setNoSigPipe(fd)

        do {
            try bindUnix(fd, path: path)
        } catch {
            Darwin.close(fd)
            throw error
        }
        guard Darwin.listen(fd, 16) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw TransportError.socket(code)
        }
        _ = chmod(path, 0o600)
        return fd
    }

    static func connect(path: String, timeout: TimeInterval) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TransportError.socket(errno) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        setNoSigPipe(fd)
        setTimeout(fd, timeout)

        do {
            try withUnixAddress(path) { addr, length in
                let code = Darwin.connect(fd, addr, length)
                guard code == 0 else { throw TransportError.notRunning }
            }
        } catch {
            Darwin.close(fd)
            throw error
        }
        return fd
    }

    static func accept(_ listenFD: Int32) -> Int32? {
        let client = Darwin.accept(listenFD, nil, nil)
        guard client >= 0 else { return nil }
        _ = fcntl(client, F_SETFD, FD_CLOEXEC)
        setNoSigPipe(client)
        return client
    }

    static func readMessage(from fd: Int32) throws -> Data {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count <= PasteControllerIPC.maxMessageBytes {
            let count = chunk.withUnsafeMutableBytes { raw in
                Darwin.read(fd, raw.baseAddress, raw.count)
            }
            if count == 0 {
                if buffer.isEmpty { throw TransportError.closed }
                break
            }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT {
                    throw TransportError.timeout
                }
                throw TransportError.socket(errno)
            }
            buffer.append(contentsOf: chunk.prefix(count))
            if let newline = buffer.firstIndex(of: 10) {
                return Data(buffer[..<newline])
            }
        }
        throw TransportError.tooLarge
    }

    static func writeMessage(_ data: Data, to fd: Int32) throws {
        var payload = data
        payload.append(10)
        try payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < payload.count {
                let count = Darwin.write(fd, raw.baseAddress?.advanced(by: offset), payload.count - offset)
                if count <= 0 {
                    if errno == EINTR { continue }
                    throw TransportError.socket(errno)
                }
                offset += count
            }
        }
    }

    private static func bindUnix(_ fd: Int32, path: String) throws {
        try withUnixAddress(path) { addr, length in
            let code = bind(fd, addr, length)
            guard code == 0 else { throw TransportError.socket(errno) }
        }
    }

    private static func setNoSigPipe(_ fd: Int32) {
        var value: Int32 = 1
        _ = setsockopt(
            fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func setTimeout(_ fd: Int32, _ timeout: TimeInterval) {
        var value = timeval(
            tv_sec: time_t(timeout),
            tv_usec: suseconds_t((timeout - floor(timeout)) * 1_000_000)
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func withUnixAddress(
        _ path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Void
    ) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else { throw TransportError.pathTooLong }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: Int8.self, capacity: capacity) { destination in
                for index in 0..<bytes.count {
                    destination[index] = bytes[index]
                }
            }
        }
        try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                try body(sockaddr, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }
    }
}
