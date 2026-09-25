import XCTest
@testable import XiaomiCodexRemote

final class AudioRecoveryTests: XCTestCase {
    func testStoppedEngineRestartsBeforeAcceptingAudio() {
        let recovery = AudioPlaybackRecovery()
        var running = false
        var restarts = 0
        XCTAssertTrue(recovery.ensureRunning(isRunning: { running }, now: 0) {
            restarts += 1
            running = true
        })
        XCTAssertEqual(restarts, 1)
        XCTAssertTrue(recovery.ensureRunning(isRunning: { running }, now: 0.01) {
            XCTFail("A healthy engine must not restart for each packet")
        })
        running = false
        XCTAssertTrue(recovery.ensureRunning(isRunning: { running }, now: 0.02) {
            running = true
            restarts += 1
        })
        XCTAssertEqual(restarts, 2)
    }

    func testFailureIsNotReadyAndRetriesAreBounded() {
        let recovery = AudioPlaybackRecovery()
        var attempts = 0
        let restart: () throws -> Void = {
            attempts += 1
            throw NSError(domain: "AudioTest", code: 1)
        }
        XCTAssertFalse(recovery.ensureRunning(isRunning: { false }, now: 0, restart: restart))
        XCTAssertFalse(recovery.ensureRunning(isRunning: { false }, now: 0.2, restart: restart))
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(recovery.ensureRunning(isRunning: { false }, now: 1.1, restart: restart))
        XCTAssertEqual(attempts, 2)
    }

    func testRestartMustActuallyProduceRunningEngine() {
        let recovery = AudioPlaybackRecovery()
        XCTAssertFalse(recovery.ensureRunning(isRunning: { false }, now: 0, restart: {}))
    }
}
