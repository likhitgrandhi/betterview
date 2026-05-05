import Foundation

actor ClaudeRunnerRegistry {
    private var runners: [UUID: ClaudeRunner] = [:]

    func runner(for chatID: UUID) -> ClaudeRunner {
        if let r = runners[chatID] { return r }
        let r = ClaudeRunner()
        runners[chatID] = r
        return r
    }

    func remove(chatID: UUID) async {
        if let r = runners.removeValue(forKey: chatID) {
            await r.stop()
        }
    }

    func stopAll() async {
        for (_, r) in runners {
            await r.stop()
        }
        runners.removeAll()
    }
}
