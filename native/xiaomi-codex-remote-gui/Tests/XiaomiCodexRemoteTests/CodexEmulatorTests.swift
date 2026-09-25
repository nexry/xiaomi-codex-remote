import XCTest
@testable import XiaomiCodexRemote

final class CodexEmulatorTests: XCTestCase {
    func testVersionCompactIDAndLightingUpdates() throws {
        let emulator = CodexEmulator()
        var messages: [CodexJSON] = []
        emulator.onSend = { messages.append($0) }
        emulator.handle(try .parse(#"{"i":0,"m":"sys.version"}"#))
        XCTAssertEqual(messages.last?["result"], .string("1.0.0"))
        emulator.handle(try .parse(#"{"id":2,"m":"v.oai.rgbcfg","p":{"keys":{"e":1}}}"#))
        XCTAssertEqual(emulator.lighting.keys, .object(["e": .number(1)]))
        emulator.handle(try .parse(#"{"id":3,"m":"v.oai.rgbcfg","p":{"keys":null}}"#))
        XCTAssertEqual(emulator.lighting.keys, .object(["e": .number(1)]))
        emulator.handle(try .parse(#"{"id":4,"m":"v.oai.thstatus","p":[{"id":0,"s":1},{"id":7,"s":2}]}"#))
        XCTAssertEqual(emulator.lighting.slots[0]?["s"], .number(1))
        XCTAssertEqual(emulator.lighting.slots.count, 6)
    }
    func testJSONPreservesNumbersAndBooleans() throws {
        let json = try CodexJSON.parse(#"{"zero":0,"one":1,"yes":true,"no":false}"#)
        XCTAssertEqual(json["zero"], .number(0))
        XCTAssertEqual(json["one"], .number(1))
        XCTAssertEqual(json["yes"], .bool(true))
        XCTAssertEqual(json["no"], .bool(false))
        XCTAssertEqual(try CodexJSON.parse(json.encodedLine()), json)
    }
    func testDeviceStatusResponse() throws {
        let emulator = CodexEmulator()
        var sent: [CodexJSON] = []
        emulator.onSend = { sent.append($0) }
        emulator.handle(try CodexJSON.parse(#"{"id":52,"method":"device.status"}"#))
        XCTAssertEqual(sent, [.object([
            "id": .number(52),
            "result": .object([
                "version": .string("1.0.0"), "profile_index": .number(0),
                "layer_index": .number(0), "battery": .number(100),
                "is_charging": .bool(false),
            ]),
        ])])
    }

    func testUnknownRequestIsAcknowledged() throws {
        let emulator = CodexEmulator()
        var sent: [CodexJSON] = []
        emulator.onSend = { sent.append($0) }
        emulator.handle(try CodexJSON.parse(#"{"id":"7","m":"future.method"}"#))
        XCTAssertEqual(sent, [.object(["id": .number(7), "result": .bool(true)])])
    }

    func testHostNotificationDoesNotReply() throws {
        let emulator = CodexEmulator()
        var count = 0
        emulator.onSend = { _ in count += 1 }
        emulator.handle(try CodexJSON.parse(#"{"m":"host.notice","p":{}}"#))
        XCTAssertEqual(count, 0)
    }

    func testKeyNotificationIncludesAgentOnlyWhenPresent() {
        let emulator = CodexEmulator()
        var sent: [CodexJSON] = []
        emulator.onSend = { sent.append($0) }
        emulator.sendKey("AG00", action: 1, agent: 0)
        emulator.sendKey("ENC_CC", action: 2, agent: nil)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0]["p"]?["ag"], .number(0))
        XCTAssertNil(sent[1]["p"]?["ag"])
    }
}
