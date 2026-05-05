import Foundation

enum AppPaths {
    nonisolated static let appName = "BetterView"

    nonisolated static var supportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static var workspacesIndex: URL {
        supportRoot.appendingPathComponent("workspaces.json", isDirectory: false)
    }

    nonisolated static func workspaceDir(_ workspaceID: UUID) -> URL {
        let dir = supportRoot
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(workspaceID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func chatsDir(for workspaceID: UUID) -> URL {
        let dir = workspaceDir(workspaceID).appendingPathComponent("chats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func chatFile(workspaceID: UUID, chatID: UUID) -> URL {
        chatsDir(for: workspaceID).appendingPathComponent("\(chatID.uuidString).json", isDirectory: false)
    }

    nonisolated static var scratchFolder: URL {
        let dir = supportRoot.appendingPathComponent("scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Workflows

    nonisolated static func workflowsDir(for workspaceID: UUID) -> URL {
        let dir = workspaceDir(workspaceID).appendingPathComponent("workflows", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func workflowFile(workspaceID: UUID, workflowID: UUID) -> URL {
        workflowsDir(for: workspaceID).appendingPathComponent("\(workflowID.uuidString).json", isDirectory: false)
    }

    nonisolated static func runsDir(workspaceID: UUID, workflowID: UUID) -> URL {
        let dir = workflowsDir(for: workspaceID)
            .appendingPathComponent(workflowID.uuidString, isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func runFile(workspaceID: UUID, workflowID: UUID, runID: UUID) -> URL {
        runsDir(workspaceID: workspaceID, workflowID: workflowID)
            .appendingPathComponent("\(runID.uuidString).json", isDirectory: false)
    }

    /// Materialized output directory inside the user's workspace folder
    /// (`<workspaceFolder>/.context/workflows/<workflowID>/<runID>/`). This
    /// is what the user sees in Finder; it stays even after the run record
    /// is deleted.
    nonisolated static func materializedRunDir(
        workspaceFolder: URL,
        workflowID: UUID,
        runID: UUID
    ) -> URL {
        let dir = workspaceFolder
            .appendingPathComponent(".context", isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
            .appendingPathComponent(workflowID.uuidString, isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
