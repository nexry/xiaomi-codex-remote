import Foundation
import Observation

/// GUI-owned runtime. Public methods and transport callbacks run on main.
@Observable
final class NativeCodexBridge {
    enum State: Equatable { case stopped, starting, running, failed(String) }
    private(set) var state: State = .stopped
    private(set) var shimConnected = false
    let socketPath: String
    var onLogLine: ((String) -> Void)?
    @ObservationIgnored private let server: CodexSocketServer
    @ObservationIgnored private let emulator = CodexEmulator()
    @ObservationIgnored private lazy var router = XiaomiInputRouter(emulator: emulator)
    @ObservationIgnored private var reassembler = CodexFrameReassembler()

    init(socketPath: String = NSTemporaryDirectory() + "codex-micro-vhid.sock") {
        self.socketPath = socketPath
        server = CodexSocketServer(path: socketPath)
        server.onFrame = { [weak self] frame in self?.receive(frame) }
        server.onConnectionChange = { [weak self] connected in
            guard let self else { return }
            self.shimConnected = connected
            self.reassembler = CodexFrameReassembler()
            if !connected { self.router.releaseAll() }
            self.onLogLine?(connected ? "Shim 已连接" : "Shim 已断开")
        }
        server.onError = { [weak self] error in
            self?.releaseHeldKeys()
            self?.onLogLine?("通信错误: \(error)")
        }
        emulator.onSend = { [weak self] message in
            guard let self else { return }
            do {
                let line = try message.encodedLine()
                for frame in CodexFrameEncoder.encode(line) { self.server.write(frame) }
                self.onLogLine?(line.trimmingCharacters(in: .newlines))
            } catch { self.onLogLine?("编码错误: \(error.localizedDescription)") }
        }
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state != .running else { return }
        state = .starting
        reassembler = CodexFrameReassembler()
        do {
            try server.start()
            state = .running
            onLogLine?("原生 Swift 协议引擎已启动")
        } catch {
            state = .failed(error.localizedDescription)
            onLogLine?("启动失败: \(error.localizedDescription)；请检查是否已有桥接服务占用 socket")
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        router.releaseAll()
        server.stop()
        shimConnected = false
        reassembler = CodexFrameReassembler()
        state = .stopped
    }

    func restart() { stop(); start() }
    func releaseHeldKeys() { router.releaseAll() }
    func handle(key: String, action: XiaomiKeyAction) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state == .running, shimConnected else { return }
        router.handle(.init(key: key, action: action))
    }

    private func receive(_ frame: Data) {
        for message in reassembler.push(frame) where message.channel == CodexChannel.rpc.rawValue {
            do { emulator.handle(try CodexJSON.parse(message.message)) }
            catch { onLogLine?("忽略无效 RPC: \(error.localizedDescription)") }
        }
    }
}
