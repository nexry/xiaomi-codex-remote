import XCTest
@testable import XiaomiCodexRemote

final class XiaomiInputRouterTests: XCTestCase {
    func testOrdinaryKeyPressReleaseAndDuplicateSuppression() {
        let emulator = CodexEmulator()
        var sent: [CodexJSON] = []
        emulator.onSend = { sent.append($0) }
        let router = XiaomiInputRouter(emulator: emulator)
        XCTAssertTrue(router.handle(.init(key: "home", action: .press)))
        XCTAssertFalse(router.handle(.init(key: "home", action: .press)))
        XCTAssertTrue(router.handle(.init(key: "home", action: .release)))
        XCTAssertFalse(router.handle(.init(key: "home", action: .release)))
        XCTAssertEqual(sent.map { $0["p"]?["act"] }, [.number(1), .number(0)])
    }

    func testRotationPressAndRepeatEmitTicksWithoutRelease() {
        let emulator = CodexEmulator()
        var sent: [CodexJSON] = []
        emulator.onSend = { sent.append($0) }
        let router = XiaomiInputRouter(emulator: emulator)
        XCTAssertTrue(router.handle(.init(key: "volume_up", action: .press)))
        XCTAssertTrue(router.handle(.init(key: "volume_up", action: .repeat)))
        XCTAssertTrue(router.handle(.init(key: "volume_up", action: .release)))
        XCTAssertEqual(sent.map { $0["p"]?["act"] }, [.number(2), .number(2)])
    }

    func testReleaseAllReleasesOnlyHeldButtons() {
        let emulator = CodexEmulator()
        var sent: [CodexJSON] = []
        emulator.onSend = { sent.append($0) }
        let router = XiaomiInputRouter(emulator: emulator)
        _ = router.handle(.init(key: "home", action: .press))
        _ = router.handle(.init(key: "volume_up", action: .press))
        router.releaseAll()
        XCTAssertEqual(sent.filter { $0["p"]?["act"] == .number(0) }.count, 1)
    }

    func testValidatedOverrideDisablesHomeAndRemapsMenu() throws {
        let mapping = try XiaomiKeyMapping.make(overrides: [
            "home": nil,
            "menu": .init(kind: .key, keycode: "AG05", agent: nil, angle: nil),
        ])
        XCTAssertNil(mapping["home"]!)
        XCTAssertEqual(mapping["menu"]!, .init(kind: .key, keycode: "AG05", agent: 5, angle: nil))
    }
}
