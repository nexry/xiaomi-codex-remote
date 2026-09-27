import AppKit
import Darwin
import Foundation

enum ChatGPTShimConfiguration {
    static let bundleIdentifier = "com.openai.codex"
    static let displayName = "ChatGPT Shim"
    static let shimResourceDirectory = "XiaomiCodexRemoteShim"
    static let frameworkRelativePath = "Contents/Frameworks/Codex Framework.framework/Codex Framework"
    static var socketPath: String { "/tmp/xiaomi-codex-remote-\(getuid()).sock" }
    static var logPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Xiaomi Codex Remote/shim.log").path
    }
}

enum ChatGPTCompatibilityState: Equatable {
    case checking
    case sourceMissing
    case needsPreparation(sourceVersion: String)
    case needsUpdate(installedVersion: String, sourceVersion: String)
    case needsRepair(reason: String)
    case preparing
    case ready(version: String)
    case failed(message: String)
}

enum ChatGPTLaunchState: Equatable {
    case idle
    case launching
    case waitingForShim
    case connected
    case failed(message: String)
}

enum ChatGPTCompatibilityError: LocalizedError {
    case invalidSource(String)
    case missingShim
    case invalidFuse(String)
    case commandFailed(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSource(message), let .invalidFuse(message),
             let .commandFailed(message), let .verificationFailed(message): return message
        case .missingShim: return "应用包中缺少 shim 文件，请重新构建 Xiaomi Codex Remote。"
        }
    }
}

/// Builds and validates the user-owned ChatGPT compatibility copy. The official
/// app is read-only; all mutations happen in a staging bundle beside the target.
final class ChatGPTCompatibilityManager {
    typealias CommandRunner = (_ executable: String, _ arguments: [String]) throws -> Void
    typealias SignatureVerifier = (_ appURL: URL) -> Bool
    typealias RunningDetector = () -> Bool

    let officialAppURL: URL
    let patchedAppURL: URL
    private let resourceURL: URL?
    private let fileManager: FileManager
    private let runCommand: CommandRunner
    private let verifySignature: SignatureVerifier
    private let isChatGPTRunning: RunningDetector

    init(
        resourceURL: URL? = Bundle.main.resourceURL,
        officialAppURL: URL? = nil,
        patchedAppURL: URL? = nil,
        fileManager: FileManager = .default,
        commandRunner: CommandRunner? = nil,
        signatureVerifier: SignatureVerifier? = nil,
        runningDetector: RunningDetector? = nil
    ) {
        self.resourceURL = resourceURL
        self.fileManager = fileManager
        self.officialAppURL = officialAppURL ?? Self.detectOfficialApp(fileManager: fileManager)
            ?? URL(fileURLWithPath: "/Applications/ChatGPT.app")
        self.patchedAppURL = patchedAppURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/ChatGPT-Patched.app")
        self.runCommand = commandRunner ?? Self.systemCommand
        self.verifySignature = signatureVerifier ?? Self.signatureIsLaunchable
        self.isChatGPTRunning = runningDetector ?? {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: ChatGPTShimConfiguration.bundleIdentifier
            ).contains(where: { !$0.isTerminated })
        }
    }

    static func detectOfficialApp(fileManager: FileManager = .default) -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/ChatGPT.app"),
        ]
        if let match = candidates.first(where: { fileManager.fileExists(atPath: $0.appendingPathComponent("Contents/Info.plist").path) }) {
            return match
        }
        guard let discovered = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: ChatGPTShimConfiguration.bundleIdentifier
        ), discovered.lastPathComponent == "ChatGPT.app" else { return nil }
        return discovered
    }

    func inspect() -> ChatGPTCompatibilityState {
        guard let sourceVersion = bundleVersion(at: officialAppURL) else { return .sourceMissing }
        guard fileManager.fileExists(atPath: patchedAppURL.path) else {
            return .needsPreparation(sourceVersion: sourceVersion)
        }
        guard let installedVersion = bundleVersion(at: patchedAppURL) else {
            return .needsRepair(reason: "兼容副本的版本信息无效")
        }
        guard installedVersion == sourceVersion else {
            return .needsUpdate(installedVersion: installedVersion, sourceVersion: sourceVersion)
        }
        do {
            try validatePreparedBundle(at: patchedAppURL)
        } catch {
            return .needsRepair(reason: error.localizedDescription)
        }
        return .ready(version: installedVersion)
    }

    func prepare() throws {
        guard !isChatGPTRunning() else {
            throw ChatGPTCompatibilityError.commandFailed("请先正常退出 ChatGPT，再准备兼容副本")
        }
        guard let sourceVersion = bundleVersion(at: officialAppURL),
              bundleIdentifier(at: officialAppURL) == ChatGPTShimConfiguration.bundleIdentifier else {
            throw ChatGPTCompatibilityError.invalidSource("没有找到有效的官方 ChatGPT.app")
        }
        guard let shimDirectory = bundledShimDirectory() else { throw ChatGPTCompatibilityError.missingShim }

        let source = officialAppURL.resolvingSymlinksInPath().standardizedFileURL
        let target = patchedAppURL.resolvingSymlinksInPath().standardizedFileURL
        guard source != target else {
            throw ChatGPTCompatibilityError.invalidSource("兼容副本不能覆盖官方 ChatGPT.app")
        }

        let parent = patchedAppURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".ChatGPT-Patched.\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent(".ChatGPT-Patched.backup.\(UUID().uuidString).app")
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: backup)
        }

        try runCommand("/usr/bin/ditto", [
            "--noextattr", "--noqtn", officialAppURL.path, staging.path,
        ])
        let embeddedShim = staging.appendingPathComponent("Contents/Resources")
            .appendingPathComponent(ChatGPTShimConfiguration.shimResourceDirectory)
        try fileManager.createDirectory(at: embeddedShim, withIntermediateDirectories: true)
        for file in ["preload.cjs", "patch.cjs"] {
            let data = try Data(contentsOf: shimDirectory.appendingPathComponent(file))
            try data.write(to: embeddedShim.appendingPathComponent(file), options: .atomic)
        }

        try writeLaunchEnvironment(in: staging)
        try ElectronFuseEditor.enableNodeOptions(in: frameworkURL(in: staging))
        try runCommand("/usr/bin/codesign", [
            "--force", "--deep", "--sign", "-", "--timestamp=none",
            // A local ad-hoc signature cannot satisfy OpenAI's restricted
            // application-group, push, and keychain entitlements. Re-sign the
            // complete bundle without those team-scoped entitlements or the
            // kernel rejects it before the process starts.
            staging.path,
        ])
        guard verifySignature(staging) else {
            throw ChatGPTCompatibilityError.verificationFailed("兼容副本签名验证失败")
        }
        guard bundleVersion(at: staging) == sourceVersion else {
            throw ChatGPTCompatibilityError.verificationFailed("兼容副本版本与官方应用不一致")
        }
        try validatePreparedBundle(at: staging)

        if fileManager.fileExists(atPath: patchedAppURL.path) {
            try fileManager.moveItem(at: patchedAppURL, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: patchedAppURL)
        } catch {
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: patchedAppURL)
            }
            throw error
        }
        try? fileManager.removeItem(at: backup)
    }

    func revealDockEntry() {
        guard fileManager.fileExists(atPath: patchedAppURL.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([patchedAppURL])
    }

    func bundledShimDirectory() -> URL? {
        guard let directory = resourceURL?.appendingPathComponent("shim") else { return nil }
        guard ["preload.cjs", "patch.cjs"].allSatisfy({
            fileManager.isReadableFile(atPath: directory.appendingPathComponent($0).path)
        }) else { return nil }
        return directory
    }

    private func validatePreparedBundle(at appURL: URL) throws {
        let embeddedShim = appURL.appendingPathComponent("Contents/Resources")
            .appendingPathComponent(ChatGPTShimConfiguration.shimResourceDirectory)
        guard ["preload.cjs", "patch.cjs"].allSatisfy({
            fileManager.isReadableFile(atPath: embeddedShim.appendingPathComponent($0).path)
        }) else { throw ChatGPTCompatibilityError.verificationFailed("兼容副本缺少内置 shim") }
        guard try ElectronFuseEditor.nodeOptionsEnabled(in: frameworkURL(in: appURL)) else {
            throw ChatGPTCompatibilityError.verificationFailed("兼容副本的 Electron fuse 未开启")
        }
        guard launchEnvironmentIsCurrent(in: appURL) else {
            throw ChatGPTCompatibilityError.verificationFailed("兼容副本的启动环境需要修复")
        }
        guard verifySignature(appURL) else {
            throw ChatGPTCompatibilityError.verificationFailed("兼容副本签名无效")
        }
    }

    private func frameworkURL(in appURL: URL) -> URL {
        appURL.appendingPathComponent(ChatGPTShimConfiguration.frameworkRelativePath)
    }

    private func bundleInfo(at appURL: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")),
              let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return nil }
        return value as? [String: Any]
    }

    private func bundleVersion(at appURL: URL) -> String? {
        bundleInfo(at: appURL)?["CFBundleVersion"] as? String
    }

    private func bundleIdentifier(at appURL: URL) -> String? {
        bundleInfo(at: appURL)?["CFBundleIdentifier"] as? String
    }

    private func expectedEnvironment() -> [String: String] {
        // The bundle is configured while it still has a staging name, but is
        // launched only after the staging bundle moves to this stable path.
        let preload = patchedAppURL.appendingPathComponent("Contents/Resources")
            .appendingPathComponent(ChatGPTShimConfiguration.shimResourceDirectory)
            .appendingPathComponent("preload.cjs").path
        return [
            "NODE_OPTIONS": "--require \"\(preload)\"",
            "CODEX_MICRO_SOCKET": ChatGPTShimConfiguration.socketPath,
            "CODEX_MICRO_SHIM_LOG": ChatGPTShimConfiguration.logPath,
        ]
    }

    private func launchEnvironmentIsCurrent(in appURL: URL) -> Bool {
        guard let environment = bundleInfo(at: appURL)?["LSEnvironment"] as? [String: String] else { return false }
        return expectedEnvironment().allSatisfy { environment[$0.key] == $0.value }
    }

    private func writeLaunchEnvironment(in appURL: URL) throws {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard var info = bundleInfo(at: appURL) else {
            throw ChatGPTCompatibilityError.invalidSource("无法读取 ChatGPT Info.plist")
        }
        info["CFBundleDisplayName"] = ChatGPTShimConfiguration.displayName
        var environment = info["LSEnvironment"] as? [String: String] ?? [:]
        expectedEnvironment().forEach { environment[$0.key] = $0.value }
        info["LSEnvironment"] = environment
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    private static func systemCommand(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        try process.run()
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ChatGPTCompatibilityError.commandFailed(message?.isEmpty == false ? message! : "命令执行失败：\(executable)")
        }
    }

    private static func signatureIsLaunchable(_ appURL: URL) -> Bool {
        guard (try? systemCommand(
            "/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path]
        )) != nil else { return false }
        guard let data = try? systemOutput(
            "/usr/bin/codesign", ["-d", "--entitlements", ":-", appURL.path]
        ) else { return false }
        guard !data.isEmpty else { return true }
        guard let value = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ), let entitlements = value as? [String: Any] else { return false }
        let restricted = [
            "com.apple.application-identifier",
            "com.apple.developer.aps-environment",
            "com.apple.developer.team-identifier",
            "com.apple.security.application-groups",
            "keychain-access-groups",
        ]
        return restricted.allSatisfy { entitlements[$0] == nil }
    }

    private static func systemOutput(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ChatGPTCompatibilityError.commandFailed("命令执行失败：\(executable)")
        }
        return data
    }
}

enum ElectronFuseEditor {
    private static let sentinel = Data("dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX".utf8)
    private static let nodeOptionsIndex: UInt64 = 2
    private static let enabled: UInt8 = 49
    private static let disabled: UInt8 = 48

    static func nodeOptionsEnabled(in binaryURL: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: binaryURL)
        defer { try? handle.close() }
        let offsets = try sentinelOffsets(in: handle)
        guard !offsets.isEmpty else {
            throw ChatGPTCompatibilityError.invalidFuse("没有找到 Electron fuse 标记")
        }
        return try offsets.allSatisfy { try state(at: $0, in: handle) == enabled }
    }

    static func enableNodeOptions(in binaryURL: URL) throws {
        let handle = try FileHandle(forUpdating: binaryURL)
        defer { try? handle.close() }
        let offsets = try sentinelOffsets(in: handle)
        guard !offsets.isEmpty, offsets.count <= 2 else {
            throw ChatGPTCompatibilityError.invalidFuse("Electron fuse 标记数量无效")
        }
        for offset in offsets {
            let current = try state(at: offset, in: handle)
            guard current == enabled || current == disabled else {
                throw ChatGPTCompatibilityError.invalidFuse("NodeOptions fuse 不可修改")
            }
        }
        for offset in offsets {
            try handle.seek(toOffset: stateOffset(for: offset))
            try handle.write(contentsOf: Data([enabled]))
        }
        try handle.synchronize()
    }

    private static func state(at sentinelOffset: UInt64, in handle: FileHandle) throws -> UInt8 {
        let headerOffset = sentinelOffset + UInt64(sentinel.count)
        try handle.seek(toOffset: headerOffset)
        guard let header = try handle.read(upToCount: 2), header.count == 2,
              header[0] == 1, header[1] > nodeOptionsIndex else {
            throw ChatGPTCompatibilityError.invalidFuse("Electron fuse 版本或长度不受支持")
        }
        try handle.seek(toOffset: stateOffset(for: sentinelOffset))
        guard let value = try handle.read(upToCount: 1)?.first else {
            throw ChatGPTCompatibilityError.invalidFuse("无法读取 NodeOptions fuse")
        }
        return value
    }

    private static func stateOffset(for sentinelOffset: UInt64) -> UInt64 {
        sentinelOffset + UInt64(sentinel.count) + 2 + nodeOptionsIndex
    }

    private static func sentinelOffsets(in handle: FileHandle) throws -> [UInt64] {
        try handle.seek(toOffset: 0)
        let chunkSize = 4 * 1024 * 1024
        let overlap = sentinel.count - 1
        var tail = Data()
        var fileOffset: UInt64 = 0
        var found: [UInt64] = []
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            var buffer = tail
            buffer.append(chunk)
            let base = fileOffset - UInt64(tail.count)
            var searchStart = buffer.startIndex
            while searchStart < buffer.endIndex,
                  let range = buffer.range(of: sentinel, options: [], in: searchStart..<buffer.endIndex) {
                let relative = buffer.distance(from: buffer.startIndex, to: range.lowerBound)
                let absolute = base + UInt64(relative)
                if found.last != absolute { found.append(absolute) }
                searchStart = buffer.index(after: range.lowerBound)
            }
            // Normalize the slice so the next chunk starts at Data index zero.
            // Data suffixes retain their original indices, which must not leak
            // into file-offset calculations for large Electron binaries.
            tail = Data(buffer.suffix(overlap))
            fileOffset += UInt64(chunk.count)
        }
        return found
    }
}
