import XCTest
@testable import XiaomiCodexRemote

final class XiaomiInputRouterTests: XCTestCase {
    func testEditorTitlesAndBindingDescriptions() {
        XCTAssertEqual(KeyMappingPage.remoteButtonTitle("up"), "上方向键")
        XCTAssertEqual(KeyMappingPage.remoteButtonTitle("back"), "返回键")
        XCTAssertEqual(KeyMappingPage.remoteButtonTitle("voice"), "语音键")
        XCTAssertEqual(KeyMappingPage.currentBindingDescription(XiaomiKeyMapping.defaults["back"]!), "对应按键：Codex Micro ACT08 键位")
        XCTAssertEqual(KeyMappingPage.currentBindingDescription(XiaomiKeyMapping.defaults["volume_up"]!), "对应按键：Codex Micro ENC_CC 逆时针旋钮")
        XCTAssertEqual(KeyMappingPage.currentBindingDescription(XiaomiKeyMapping.defaults["up"]!), "对应按键：Codex Micro JOY_UP 摇杆上")
        XCTAssertEqual(KeyMappingPage.currentBindingDescription(nil), "对应按键：未设置")
    }
    func testFirstEditorSessionStartsWithSavedBindingAndNoChanges() {
        let original = XiaomiKeyMapping.defaults["ok"]!
        let session = BindingEditorSession(id: "ok", binding: original)
        XCTAssertEqual(session.id, "ok")
        XCTAssertEqual(session.originalBinding, original)
        XCTAssertEqual(session.binding, original)
        XCTAssertFalse(session.hasChanges)
        XCTAssertFalse(session.isVoiceLocked)
        XCTAssertNil(session.pendingBinding)

        // The sheet receives this object directly, not a parent's optional state.
        let sheetSession = session
        sheetSession.binding = nil
        XCTAssertNil(session.binding)
        XCTAssertTrue(session.hasChanges)
        XCTAssertEqual(session.originalBinding, original)
        session.binding = original
        XCTAssertFalse(session.hasChanges)
    }

    func testEditorSessionsDoNotReuseDraftOrPendingBinding() {
        let first = BindingEditorSession(id: "ok", binding: XiaomiKeyMapping.defaults["ok"]!)
        first.binding = nil
        first.pendingBinding = XiaomiKeyMapping.voiceBinding
        let second = BindingEditorSession(id: "home", binding: XiaomiKeyMapping.defaults["home"]!)
        XCTAssertEqual(second.binding?.keycode, "AG00")
        XCTAssertFalse(second.hasChanges)
        XCTAssertNil(second.pendingBinding)

        let unbound = BindingEditorSession(id: "tv", binding: nil)
        XCTAssertNil(unbound.binding)
        XCTAssertFalse(unbound.hasChanges)
        let voice = BindingEditorSession(id: "voice", binding: XiaomiKeyMapping.voiceBinding)
        XCTAssertTrue(voice.isVoiceLocked)
        XCTAssertEqual(voice.binding?.keycode, "ACT10")
        XCTAssertFalse(voice.hasChanges)
    }

    func testBindingLabelsUseKeyIdentifiersRatherThanHostActions() {
        for code in ["AG00", "ACT06", "ACT07", "ACT08", "ACT09", "ACT10", "ACT11", "ACT12", "ENC_CC", "ENC_CW", "ENC_CLK"] {
            let kind: XiaomiBindingKind = ["ENC_CC", "ENC_CW"].contains(code) ? .rotate : .key
            XCTAssertEqual(KeyMappingPage.bindingLabel(.init(kind: kind, keycode: code, agent: code == "AG00" ? 0 : nil, angle: nil)), code)
        }
        XCTAssertEqual(KeyMappingPage.bindingLabel(nil), "未绑定")
        XCTAssertEqual(KeyMappingPage.bindingLabel(.init(kind: .joystick, keycode: nil, agent: nil, angle: 0.75)), "摇杆上")
    }

    func testOKDefaultsToACT12WithPressAndRelease() {
        let emulator = CodexEmulator()
        var sent: [CodexJSON] = []
        emulator.onSend = { sent.append($0) }
        let router = XiaomiInputRouter(emulator: emulator)
        XCTAssertTrue(router.handle(.init(key: "ok", action: .press)))
        XCTAssertTrue(router.handle(.init(key: "ok", action: .release)))
        XCTAssertEqual(sent.map { $0["p"]?["k"] }, [.string("ACT12"), .string("ACT12")])
        XCTAssertEqual(sent.map { $0["p"]?["act"] }, [.number(1), .number(0)])
    }

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

    func testVoiceBindingCannotBeChangedOrDisabled() throws {
        let remapped = try XiaomiKeyMapping.make(overrides: [
            "voice": .init(kind: .key, keycode: "ACT08", agent: nil, angle: nil),
        ])
        let disabled = try XiaomiKeyMapping.make(overrides: ["voice": nil])

        XCTAssertEqual(remapped["voice"]!, XiaomiKeyMapping.voiceBinding)
        XCTAssertEqual(disabled["voice"]!, XiaomiKeyMapping.voiceBinding)
    }

    func testTVKeyStartsUnboundAndCanBeConfigured() throws {
        XCTAssertTrue(XiaomiKeyMapping.defaults.keys.contains("tv"))
        XCTAssertNil(XiaomiKeyMapping.defaults["tv"]!)

        let mapping = try XiaomiKeyMapping.make(overrides: [
            "tv": .init(kind: .key, keycode: "AG05", agent: nil, angle: nil),
        ])
        XCTAssertEqual(mapping["tv"]!, .init(kind: .key, keycode: "AG05", agent: 5, angle: nil))
    }
}
