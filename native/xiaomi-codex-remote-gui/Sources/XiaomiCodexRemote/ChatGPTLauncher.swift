import Foundation
import AppKit

/// Launches ChatGPT.app with the Codex Micro node-hid shim injected.
@Observable
final class ChatGPTLauncher {
    private(set) var chatGPTPath: String?
    private(set) var isLaunched: Bool = false

    private static let defaultPaths = [
        "/Applications/ChatGPT.app",
        NSHomeDirectory() + "/Applications/ChatGPT.app",
    ]

    private let resourceURL: URL?

    init(resourceURL: URL? = Bundle.main.resourceURL) {
        self.resourceURL = resourceURL
        chatGPTPath = UserDefaults.standard.string(forKey: "chatGPTPath") ?? Self.detectChatGPTPath()
    }

    func resolveShimPath(debugProjectRoot: String? = nil) -> String? {
        func preload(in root: URL) -> String? {
            let directory = root.appendingPathComponent("shim")
            guard ["preload.cjs", "patch.cjs"].allSatisfy({
                FileManager.default.isReadableFile(atPath: directory.appendingPathComponent($0).path)
            }) else { return nil }
            return directory.appendingPathComponent("preload.cjs").path
        }
        if let resourceURL, let path = preload(in: resourceURL) { return path }
        #if DEBUG
        if let debugProjectRoot { return preload(in: URL(fileURLWithPath: debugProjectRoot)) }
        #endif
        return nil
    }

    // MARK: - Detection

    static func detectChatGPTPath() -> String? {
        for path in defaultPaths {
            if FileManager.default.fileExists(atPath: path + "/Contents/Info.plist") {
                return path
            }
        }
        // Native LaunchServices lookup by bundle identifier (does not touch filesystem or trigger TCC)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat") {
            return appURL.path
        }
        return nil
    }

    func setChatGPTPath(_ path: String) {
        chatGPTPath = path
        UserDefaults.standard.set(path, forKey: "chatGPTPath")
    }

    // MARK: - Launch

    /// Launch ChatGPT with shim injection. This must only follow an explicit user action.
    @discardableResult
    func launch(socketPath: String) -> Bool {
        guard let appPath = chatGPTPath else {
            print("[ChatGPT] ChatGPT.app not found")
            return false
        }

        let infoPath = appPath + "/Contents/Info.plist"
        guard let dict = NSDictionary(contentsOfFile: infoPath),
              let execName = dict["CFBundleExecutable"] as? String else {
            print("[ChatGPT] Cannot read CFBundleExecutable from \(infoPath)")
            return false
        }

        let binPath = appPath + "/Contents/MacOS/" + execName
        guard FileManager.default.isExecutableFile(atPath: binPath) else {
            print("[ChatGPT] Executable not found: \(binPath)")
            return false
        }

        guard let shimPath = resolveShimPath() else {
            print("[ChatGPT] Bundled shim missing. Rebuild Xiaomi Codex Remote with bundle-app.sh.")
            return false
        }

        let logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Xiaomi Codex Remote")
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            print("[ChatGPT] Cannot create log directory: \(error.localizedDescription)")
            return false
        }

        // Quit existing ChatGPT instance
        let quitProc = Process()
        quitProc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        quitProc.arguments = ["-e", "quit app \"ChatGPT\""]
        quitProc.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        quitProc.standardOutput = FileHandle.nullDevice
        quitProc.standardError = FileHandle.nullDevice
        do { try quitProc.run() }
        catch { return false }
        quitProc.waitUntilExit()

        Thread.sleep(forTimeInterval: 1.0)

        // Launch with shim environment
        let logPath = logDirectory.appendingPathComponent("shim.log").path

        var env = ProcessInfo.processInfo.environment
        let quotedPath = shimPath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        env["NODE_OPTIONS"] = "--require \"\(quotedPath)\""
        env["CODEX_MICRO_SOCKET"] = socketPath
        env["CODEX_MICRO_SHIM_LOG"] = logPath

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binPath)
        proc.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        proc.environment = env

        do {
            try proc.run()
            DispatchQueue.main.async { self.isLaunched = true }
            print("[ChatGPT] Launched \(execName) with shim (socket: \(socketPath))")
            return true
        } catch {
            print("[ChatGPT] Launch failed: \(error.localizedDescription)")
            return false
        }
    }
}
