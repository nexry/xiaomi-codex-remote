import XCTest
@testable import XiaomiCodexRemote

final class CodexFramingTests: XCTestCase {
    func testUTF8AcrossFrameBoundary() {
        let source = "{\"text\":\"" + String(repeating: "a", count: 51) + "遥控器\"}"
        var reassembler = CodexFrameReassembler()
        XCTAssertEqual(CodexFrameEncoder.encode(source).flatMap { reassembler.push($0) }.map(\.message), [source])
    }
    func testEncoderMatchesSharedFixtures() throws {
        for fixture in try FrameFixture.load() {
            let frames = CodexFrameEncoder.encode(fixture.message, channel: fixture.channel)
            XCTAssertEqual(frames, fixture.frames.map(Data.init(hex:)), fixture.name)
        }
    }

    func testReassemblesBareRPCObjectAcrossFrames() throws {
        let fixture = try XCTUnwrap(try FrameFixture.load().first { $0.name == "host device status request" })
        var reassembler = CodexFrameReassembler()
        let messages = fixture.frames.flatMap { reassembler.push(Data(hex: $0)) }
        XCTAssertEqual(messages, [.init(channel: 2, message: fixture.message)])
    }

    func testReassemblerAcceptsReportIDStrippedFramesAndEscapedBraces() {
        let source = #"{"id":7,"method":"x","params":{"value":"}\\\"{"}}"#
        var reassembler = CodexFrameReassembler()
        let output = CodexFrameEncoder.encode(source).flatMap { reassembler.push($0.dropFirst()) }
        XCTAssertEqual(output.map(\.message), [source])
    }

    func testDebugChannelUsesNewlines() {
        var reassembler = CodexFrameReassembler()
        let messages = CodexFrameEncoder.encode("one\ntwo\n", channel: CodexChannel.debug.rawValue)
            .flatMap { reassembler.push($0) }
        XCTAssertEqual(messages.map(\.message), ["one", "two"])
    }
}
