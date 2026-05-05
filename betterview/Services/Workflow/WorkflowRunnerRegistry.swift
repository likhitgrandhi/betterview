import Foundation

actor WorkflowRunnerRegistry {
    private var runners: [UUID: WorkflowRunner] = [:]

    func runner(for runID: UUID) -> WorkflowRunner {
        if let r = runners[runID] { return r }
        let r = WorkflowRunner()
        runners[runID] = r
        return r
    }

    func remove(runID: UUID) async {
        if let r = runners.removeValue(forKey: runID) {
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
