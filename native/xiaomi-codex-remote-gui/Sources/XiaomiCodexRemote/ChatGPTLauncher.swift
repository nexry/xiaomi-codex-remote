import AppKit
import Foundation

/// Owns the user-visible compatibility state and launches the managed ChatGPT
/// copy. Preparation and launch are always initiated by an explicit user action.
@Observable
final class ChatGPTLauncher {
    private(set) var compatibilityState: ChatGPTCompatibilityState = .checking
    private(set) var launchState: ChatGPTLaunchState = .idle
    let compatibilityManager: ChatGPTCompatibilityManager

    var chatGPTPath: String? {
        if case .ready = compatibilityState { return compatibilityManager.patchedAppURL.path }
        return nil
    }

    init(
        resourceURL: URL? = Bundle.main.resourceURL,
        officialAppURL: URL? = nil,
        patchedAppURL: URL? = nil,
        compatibilityManager: ChatGPTCompatibilityManager? = nil
    ) {
        self.compatibilityManager = compatibilityManager ?? ChatGPTCompatibilityManager(
            resourceURL: resourceURL,
            officialAppURL: officialAppURL,
            patchedAppURL: patchedAppURL
        )
        compatibilityState = self.compatibilityManager.inspect()
    }

    func resolveShimPath(debugProjectRoot: String? = nil) -> String? {
        if let directory = compatibilityManager.bundledShimDirectory() {
            return directory.appendingPathComponent("preload.cjs").path
        }
        #if DEBUG
        if let debugProjectRoot {
            let directory = URL(fileURLWithPath: debugProjectRoot).appendingPathComponent("shim")
            if ["preload.cjs", "patch.cjs"].allSatisfy({
                FileManager.default.isReadableFile(atPath: directory.appendingPathComponent($0).path)
            }) { return directory.appendingPathComponent("preload.cjs").path }
        }
        #endif
        return nil
    }

    func refreshCompatibility() {
        guard compatibilityState != .preparing else { return }
        compatibilityState = compatibilityManager.inspect()
    }

    func prepareCompatibility(completion: @escaping (Result<Void, Error>) -> Void) {
        guard compatibilityState != .preparing else { return }
        compatibilityState = .preparing
        let manager = compatibilityManager
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<Void, Error>
            do {
                try manager.prepare()
                result = .success(())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.compatibilityState = manager.inspect()
                case let .failure(error):
                    self.compatibilityState = .failed(message: error.localizedDescription)
                }
                completion(result)
            }
        }
    }

    func revealDockEntry() {
        compatibilityManager.revealDockEntry()
    }

    func launch(socketPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard case .ready = compatibilityState else {
            completion(.failure(ChatGPTCompatibilityError.verificationFailed("请先准备或修复 ChatGPT 兼容副本")))
            return
        }
        if launchState == .connected,
           let running = NSRunningApplication.runningApplications(
               withBundleIdentifier: ChatGPTShimConfiguration.bundleIdentifier
           ).first(where: { !$0.isTerminated }) {
            running.activate(options: [.activateAllWindows])
            completion(.success(()))
            return
        }
        launchState = .launching
        let appURL = compatibilityManager.patchedAppURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<Void, Error>
            do {
                try Self.stopRunningChatGPT()
                try Self.launchApp(at: appURL, socketPath: socketPath)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    if self.launchState != .connected { self.launchState = .waitingForShim }
                    self.scheduleConnectionTimeout()
                case let .failure(error):
                    self.launchState = .failed(message: error.localizedDescription)
                }
                completion(result)
            }
        }
    }

    func shimConnectionChanged(_ connected: Bool) {
        if connected {
            launchState = .connected
        } else if launchState == .connected {
            launchState = .failed(message: "Shim 连接已断开")
        }
    }

    private func scheduleConnectionTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.launchState == .waitingForShim else { return }
            self.launchState = .failed(message: "ChatGPT 已打开，但 Shim 未在 10 秒内连接")
        }
    }

    private static func stopRunningChatGPT() throws {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: ChatGPTShimConfiguration.bundleIdentifier
        )
        for application in running { _ = application.terminate() }
        let deadline = Date().addingTimeInterval(8)
        while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard running.allSatisfy(\.isTerminated) else {
            throw ChatGPTCompatibilityError.commandFailed("ChatGPT 未能正常退出，请保存工作后手动退出再重试")
        }
    }

    private static func launchApp(at appURL: URL, socketPath: String) throws {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL),
              let executable = info["CFBundleExecutable"] as? String else {
            throw ChatGPTCompatibilityError.invalidSource("兼容副本的启动信息无效")
        }
        let binary = appURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw ChatGPTCompatibilityError.invalidSource("兼容副本的可执行文件不存在")
        }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: ChatGPTShimConfiguration.logPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let preload = appURL.appendingPathComponent("Contents/Resources")
            .appendingPathComponent(ChatGPTShimConfiguration.shimResourceDirectory)
            .appendingPathComponent("preload.cjs").path
        var environment = ProcessInfo.processInfo.environment
        environment["NODE_OPTIONS"] = "--require \"\(preload)\""
        environment["CODEX_MICRO_SOCKET"] = socketPath
        environment["CODEX_MICRO_SHIM_LOG"] = ChatGPTShimConfiguration.logPath

        let process = Process()
        process.executableURL = binary
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        process.environment = environment
        try process.run()
    }
}
