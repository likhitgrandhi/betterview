import Foundation

actor WorkflowStore {
    func workflows(in workspaceID: UUID) -> [Workflow] {
        let dir = AppPaths.workflowsDir(for: workspaceID)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let items: [Workflow] = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let wf = try? JSONDecoder.iso.decode(Workflow.self, from: data)
                else { return nil }
                return wf
            }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ workflow: Workflow) throws {
        let url = AppPaths.workflowFile(workspaceID: workflow.workspaceID, workflowID: workflow.id)
        let data = try JSONEncoder.iso.encode(workflow)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    func delete(workspaceID: UUID, workflowID: UUID) {
        let url = AppPaths.workflowFile(workspaceID: workspaceID, workflowID: workflowID)
        try? FileManager.default.removeItem(at: url)
        // Also clear runs directory.
        let runDir = AppPaths.workflowsDir(for: workspaceID)
            .appendingPathComponent(workflowID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: runDir)
    }

    // MARK: - Runs

    func runs(workspaceID: UUID, workflowID: UUID) -> [WorkflowRun] {
        let dir = AppPaths.runsDir(workspaceID: workspaceID, workflowID: workflowID)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let items: [WorkflowRun] = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let run = try? JSONDecoder.iso.decode(WorkflowRun.self, from: data)
                else { return nil }
                return run
            }
        return items.sorted { $0.startedAt > $1.startedAt }
    }

    func saveRun(_ run: WorkflowRun) throws {
        let url = AppPaths.runFile(workspaceID: run.workspaceID, workflowID: run.workflowID, runID: run.id)
        let data = try JSONEncoder.iso.encode(run)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    func deleteRun(workspaceID: UUID, workflowID: UUID, runID: UUID) {
        let url = AppPaths.runFile(workspaceID: workspaceID, workflowID: workflowID, runID: runID)
        try? FileManager.default.removeItem(at: url)
    }
}
