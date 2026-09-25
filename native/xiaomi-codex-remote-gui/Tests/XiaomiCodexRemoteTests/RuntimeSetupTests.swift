import XCTest
@testable import XiaomiCodexRemote

final class RuntimeSetupTests: XCTestCase {
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

private final class StubAccess: HIDAccessProviding {
    let status: HIDAccessStatus
    var requests = 0
    init(status: HIDAccessStatus) { self.status = status }
    func request() -> Bool { requests += 1; return false }
}
