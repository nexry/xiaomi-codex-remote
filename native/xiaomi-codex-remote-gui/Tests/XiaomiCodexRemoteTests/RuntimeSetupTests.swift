import XCTest
@testable import XiaomiCodexRemote

final class RuntimeSetupTests: XCTestCase {
    func testPowerPreparationStopsHostBeforeGeneratingCopy() throws {
        var events: [String] = []
        var ready = false
        try RemoteLaunchPreparation.run(
            stopHost: { events.append("stop") },
            inspect: { ready ? .ready(version: "1") : .needsPreparation(sourceVersion: "1") },
            prepare: { events.append("prepare"); ready = true }
        )
        XCTAssertEqual(events, ["stop", "prepare"])
    }

    func testPowerPreparationSkipsReadyCopyAndAbortsWhenExitFails() throws {
        var prepared = false
        try RemoteLaunchPreparation.run(stopHost: {}, inspect: { .ready(version: "1") }, prepare: { prepared = true })
        XCTAssertFalse(prepared)
        XCTAssertThrowsError(try RemoteLaunchPreparation.run(
            stopHost: { throw ChatGPTCompatibilityError.commandFailed("exit failed") },
            inspect: { .needsUpdate(installedVersion: "1", sourceVersion: "2") },
            prepare: { prepared = true }
        ))
        XCTAssertFalse(prepared)
        XCTAssertThrowsError(try RemoteLaunchPreparation.run(
            stopHost: { XCTFail("Missing host must not exit applications") },
            inspect: { .sourceMissing }, prepare: { XCTFail("Missing host must not prepare") }
        ))
    }

    func testBundledShimDoesNotNeedRepository() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shim = root.appendingPathComponent("shim")
        try FileManager.default.createDirectory(at: shim, withIntermediateDirectories: true)
        try Data().write(to: shim.appendingPathComponent("preload.cjs"))
        let launcher = ChatGPTLauncher(resourceURL: root)
        XCTAssertNil(launcher.resolveShimPath())
        try Data().write(to: shim.appendingPathComponent("patch.cjs"))
        XCTAssertEqual(launcher.resolveShimPath(), shim.appendingPathComponent("preload.cjs").path)
    }

    func testElectronFuseEditorEnablesEveryArchitectureSlice() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var data = Data(repeating: 7, count: 31)
        data.append(fuseWire(nodeOptions: 48))
        data.append(Data(repeating: 9, count: 53))
        data.append(fuseWire(nodeOptions: 48))
        try data.write(to: file)

        XCTAssertFalse(try ElectronFuseEditor.nodeOptionsEnabled(in: file))
        try ElectronFuseEditor.enableNodeOptions(in: file)
        XCTAssertTrue(try ElectronFuseEditor.nodeOptionsEnabled(in: file))
    }

    func testElectronFuseEditorFindsSentinelAfterFirstReadChunk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var data = Data(repeating: 7, count: 4 * 1024 * 1024 + 17)
        data.append(fuseWire(nodeOptions: 48))
        try data.write(to: file)

        XCTAssertFalse(try ElectronFuseEditor.nodeOptionsEnabled(in: file))
        try ElectronFuseEditor.enableNodeOptions(in: file)
        XCTAssertTrue(try ElectronFuseEditor.nodeOptionsEnabled(in: file))
    }

    func testCompatibilityManagerPreparesAndValidatesManagedCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let official = root.appendingPathComponent("ChatGPT.app")
        let patched = root.appendingPathComponent("Applications/ChatGPT-for-XiaomiRemote.app")
        let resources = root.appendingPathComponent("ProductResources")
        try makeFakeChatGPT(at: official, version: "200", nodeOptions: 48)
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("shim"), withIntermediateDirectories: true)
        try Data("preload".utf8).write(to: resources.appendingPathComponent("shim/preload.cjs"))
        try Data("patch".utf8).write(to: resources.appendingPathComponent("shim/patch.cjs"))
        var commands: [(String, [String])] = []

        let manager = ChatGPTCompatibilityManager(
            resourceURL: resources,
            officialAppURL: official,
            patchedAppURL: patched,
            commandRunner: { executable, arguments in
                commands.append((executable, arguments))
                if executable == "/usr/bin/ditto" {
                    try FileManager.default.copyItem(
                        at: URL(fileURLWithPath: arguments[arguments.count - 2]),
                        to: URL(fileURLWithPath: arguments[arguments.count - 1])
                    )
                }
            },
            signatureVerifier: { _ in true },
            runningDetector: { false }
        )

        XCTAssertEqual(manager.inspect(), .needsPreparation(sourceVersion: "200"))
        try manager.prepare()
        XCTAssertEqual(manager.inspect(), .ready(version: "200"))
        XCTAssertTrue(try ElectronFuseEditor.nodeOptionsEnabled(
            in: patched.appendingPathComponent(ChatGPTShimConfiguration.frameworkRelativePath)
        ))
        let info = try XCTUnwrap(readPlist(at: patched.appendingPathComponent("Contents/Info.plist")))
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "ChatGPT 遥控版")
        let environment = try XCTUnwrap(info["LSEnvironment"] as? [String: String])
        XCTAssertEqual(environment["CODEX_MICRO_SOCKET"], ChatGPTShimConfiguration.socketPath)
        XCTAssertTrue(environment["NODE_OPTIONS"]?.contains("XiaomiCodexRemoteShim/preload.cjs") == true)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: patched.appendingPathComponent("Contents/Resources/XiaomiCodexRemoteShim/patch.cjs").path
        ))
        let signing = try XCTUnwrap(commands.first(where: { $0.0 == "/usr/bin/codesign" }))
        XCTAssertFalse(signing.1.contains(where: { $0.contains("preserve-metadata") }))
        let copying = try XCTUnwrap(commands.first(where: { $0.0 == "/usr/bin/ditto" }))
        XCTAssertTrue(copying.1.contains("--noextattr"))
        XCTAssertTrue(copying.1.contains("--noqtn"))
        var legacyInfo = info
        legacyInfo["CFBundleDisplayName"] = "ChatGPT Shim"
        let legacyData = try PropertyListSerialization.data(fromPropertyList: legacyInfo, format: .xml, options: 0)
        try legacyData.write(to: patched.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(manager.inspect(), .needsRepair(reason: "请重新设置遥控支持，将原有副本更新为「ChatGPT 遥控版」。"))
    }

    func testCompatibilityManagerReportsOutdatedAndBrokenCopies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let official = root.appendingPathComponent("ChatGPT.app")
        let patched = root.appendingPathComponent("Applications/ChatGPT-for-XiaomiRemote.app")
        try makeFakeChatGPT(at: official, version: "300", nodeOptions: 48)
        try makeFakeChatGPT(at: patched, version: "299", nodeOptions: 49)
        let manager = ChatGPTCompatibilityManager(
            resourceURL: root,
            officialAppURL: official,
            patchedAppURL: patched,
            signatureVerifier: { _ in true },
            runningDetector: { false }
        )
        XCTAssertEqual(manager.inspect(), .needsUpdate(installedVersion: "299", sourceVersion: "300"))

        var info = try XCTUnwrap(readPlist(at: patched.appendingPathComponent("Contents/Info.plist")))
        info["CFBundleVersion"] = "300"
        try writePlist(info, to: patched.appendingPathComponent("Contents/Info.plist"))
        guard case .needsRepair = manager.inspect() else {
            return XCTFail("Expected a repair state when the embedded shim is missing")
        }
    }

    func testDeniedHIDAccessNeverStartsMonitor() {
        let provider = StubAccess(status: .denied)
        let monitor = HIDRemoteMonitor(accessProvider: provider)
        var status: HIDMonitorStatus?
        monitor.onStatus = { status = $0 }
        monitor.start()
        XCTAssertEqual(status, .permissionDenied)
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertEqual(provider.requests, 0)
    }

    func testUnknownHIDAccessRequestsOnlyOnce() {
        let provider = StubAccess(status: .unknown)
        let monitor = HIDRemoteMonitor(accessProvider: provider)
        var status: HIDMonitorStatus?
        monitor.onStatus = { status = $0 }
        monitor.start()
        monitor.start()
        XCTAssertEqual(provider.requests, 1)
        XCTAssertEqual(status, .permissionRequired)
        XCTAssertFalse(monitor.isMonitoring)
    }
}

private func fuseWire(nodeOptions: UInt8) -> Data {
    var data = Data("dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX".utf8)
    data.append(contentsOf: [1, 9, 48, 49, nodeOptions, 48, 49, 49, 48, 48, 49])
    return data
}

private func makeFakeChatGPT(at app: URL, version: String, nodeOptions: UInt8) throws {
    let contents = app.appendingPathComponent("Contents")
    let framework = app.appendingPathComponent(ChatGPTShimConfiguration.frameworkRelativePath)
    try FileManager.default.createDirectory(at: framework.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
    try fuseWire(nodeOptions: nodeOptions).write(to: framework)
    try writePlist([
        "CFBundleIdentifier": ChatGPTShimConfiguration.bundleIdentifier,
        "CFBundleVersion": version,
        "CFBundleShortVersionString": version,
        "CFBundleExecutable": "ChatGPT",
        "LSEnvironment": ["MallocNanoZone": "0"],
    ], to: contents.appendingPathComponent("Info.plist"))
}

private func readPlist(at url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url),
          let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    else { return nil }
    return value as? [String: Any]
}

private func writePlist(_ value: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    try data.write(to: url)
}

private final class StubAccess: HIDAccessProviding {
    let status: HIDAccessStatus
    var requests = 0
    init(status: HIDAccessStatus) { self.status = status }
    func request() -> Bool { requests += 1; return false }
}
