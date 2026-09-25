import Foundation

/// Main-thread recovery gate; packets must not trigger an unbounded restart loop.
final class AudioPlaybackRecovery {
    private var nextAttempt: TimeInterval = 0
    var onFailure: ((String) -> Void)?

    func ensureRunning(
        isRunning: () -> Bool,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        restart: () throws -> Void
    ) -> Bool {
        if isRunning() {
            nextAttempt = 0
            return true
        }
        guard now >= nextAttempt else { return false }
        nextAttempt = now + 1
        do {
            try restart()
            guard isRunning() else {
                onFailure?("启动完成后音频引擎仍未运行")
                return false
            }
            nextAttempt = 0
            return true
        } catch {
            onFailure?(error.localizedDescription)
            return false
        }
    }
}
