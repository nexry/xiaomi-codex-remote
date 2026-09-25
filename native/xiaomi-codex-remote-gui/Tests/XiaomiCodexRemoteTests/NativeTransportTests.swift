import Darwin
import XCTest
@testable import XiaomiCodexRemote

final class UnixTestClient {
    private var fd: Int32
    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENOTSOCK) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd); fd = -1
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyBytes(from: $0) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED
            Darwin.close(fd); fd = -1
            throw POSIXError(code)
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
    }
    func write(_ data: Data) throws {
        let count = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
        guard count == data.count else { throw POSIXError(.EIO) }
    }
    func read(count: Int) throws -> Data {
        var output = Data()
        let deadline = Date().addingTimeInterval(2)
        while output.count < count && Date() < deadline {
            var bytes = [UInt8](repeating: 0, count: count - output.count)
            let n = Darwin.read(fd, &bytes, bytes.count)
            if n > 0 { output.append(contentsOf: bytes.prefix(n)) }
            else if n == 0 { throw POSIXError(.ECONNRESET) }
            else if errno != EAGAIN && errno != EINTR { throw POSIXError(.EIO) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        guard output.count == count else { throw POSIXError(.ETIMEDOUT) }
        return output
    }
    func close() { if fd >= 0 { Darwin.close(fd); fd = -1 } }
    deinit { close() }
}

func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    let deadline = Date().addingTimeInterval(2)
    while !predicate() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
    }
    XCTAssertTrue(predicate(), file: file, line: line)
}

final class NativeTransportTests: XCTestCase {
    func testExistingJavaScriptShimTalksToNativeBridge() throws {
        let bridge = NativeCodexBridge(socketPath: "/tmp/ac-\(UUID().uuidString).sock")
        bridge.start()
        defer { bridge.stop() }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let script = try XCTUnwrap(Bundle.module.url(forResource: "native-shim-client", withExtension: "cjs", subdirectory: "Fixtures"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", script.path, root.path, bridge.socketPath]
        try process.run()
        let deadline = Date().addingTimeInterval(6)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        if process.isRunning { process.terminate(); XCTFail("Shim test exceeded deadline"); return }
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testSecondServerCannotTakeOverActiveSocket() throws {
        let path = "/tmp/ac-\(UUID().uuidString).sock"
        let first = CodexSocketServer(path: path)
        try first.start()
        defer { first.stop() }
        let second = CodexSocketServer(path: path)
        XCTAssertThrowsError(try second.start())
        second.stop()
        let client = try UnixTestClient(path: path)
        var connected = false
        first.onConnectionChange = { connected = $0 }
        eventually { connected }
        client.close()
    }

    func testDisconnectClearsHeldStateBeforeReconnect() throws {
        let bridge = NativeCodexBridge(socketPath: "/tmp/ac-\(UUID().uuidString).sock")
        bridge.start()
        defer { bridge.stop() }
        let first = try UnixTestClient(path: bridge.socketPath)
        eventually { bridge.shimConnected }
        bridge.handle(key: "home", action: .press)
        _ = try first.read(count: 64)
        first.close()
        eventually { !bridge.shimConnected }
        let next = try UnixTestClient(path: bridge.socketPath)
        eventually { bridge.shimConnected }
        bridge.handle(key: "home", action: .press)
        var reassembler = CodexFrameReassembler()
        let message = try XCTUnwrap(reassembler.push(next.read(count: 64)).first)
        XCTAssertEqual(try CodexJSON.parse(message.message)["p"]?["act"], .number(1))
    }
    func testSocketFragmentsReconnectsAndCleansUp() throws {
        let path = "/tmp/ac-\(UUID().uuidString).sock"
        let server = CodexSocketServer(path: path)
        defer { server.stop() }
        var frames: [Data] = []
        var connections = 0
        server.onFrame = { frames.append($0) }
        server.onConnectionChange = { if $0 { connections += 1 } }
        try server.start()
        let first = try UnixTestClient(path: path)
        eventually { connections == 1 }
        try first.write(Data(repeating: 42, count: 17))
        try first.write(Data(repeating: 42, count: 111))
        eventually { frames.count == 2 }
        XCTAssertEqual(frames, Array(repeating: Data(repeating: 42, count: 64), count: 2))
        first.close()
        let second = try UnixTestClient(path: path)
        eventually { connections == 2 }
        server.write(Data(repeating: 75, count: 64))
        XCTAssertEqual(try second.read(count: 64), Data(repeating: 75, count: 64))
        second.close()
        server.stop()
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        try server.start()
    }

    func testServerDoesNotRemoveExistingFileOrActiveSocket() throws {
        let path = "/tmp/ac-\(UUID().uuidString).sock"
        let data = Data("keep".utf8)
        try data.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let server = CodexSocketServer(path: path)
        XCTAssertThrowsError(try server.start())
        server.stop()
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), data)
    }

    func testServerReclaimsStaleSocketFromInterruptedProcess() throws {
        let path = "/tmp/ac-\(UUID().uuidString).sock"
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = path.utf8CString
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyBytes(from: $0) }
        }
        let staleFD = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(staleFD, 0)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(staleFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)
        Darwin.close(staleFD)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        let server = CodexSocketServer(path: path)
        defer {
            server.stop()
            Darwin.unlink(path)
        }
        try server.start()
        let client = try UnixTestClient(path: path)
        client.close()
    }

    func testNativeBridgeRPCKeysAndStopRelease() throws {
        let path = "/tmp/ac-\(UUID().uuidString).sock"
        let bridge = NativeCodexBridge(socketPath: path)
        bridge.start()
        defer { bridge.stop() }
        let client = try UnixTestClient(path: path)
        eventually { bridge.shimConnected }
        for frame in CodexFrameEncoder.encode(#"{"id":1,"method":"device.status"}"#) {
            try client.write(frame)
        }
        var reassembler = CodexFrameReassembler()
        let response = reassembler.push(try client.read(count: 64)) + reassembler.push(try client.read(count: 64))
        let parsed = try CodexJSON.parse(XCTUnwrap(response.first).message)
        XCTAssertEqual(parsed["id"], .number(1))
        XCTAssertEqual(parsed["result"]?["battery"], .number(100))
        bridge.handle(key: "home", action: .press)
        let press = reassembler.push(try client.read(count: 64))
        XCTAssertEqual(try CodexJSON.parse(XCTUnwrap(press.first).message)["p"]?["act"], .number(1))
        bridge.stop()
        let release = reassembler.push(try client.read(count: 64))
        XCTAssertEqual(try CodexJSON.parse(XCTUnwrap(release.first).message)["p"]?["act"], .number(0))
        XCTAssertFalse(bridge.shimConnected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}
