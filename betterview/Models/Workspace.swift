import Foundation

struct Workspace: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var folderURL: URL
    var isScratch: Bool
    var createdAt: Date
    var lastOpenedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        folderURL: URL,
        isScratch: Bool = false,
        createdAt: Date = .now,
        lastOpenedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.folderURL = folderURL
        self.isScratch = isScratch
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
    }
}

struct WorkspaceIndex: Codable {
    var workspaces: [Workspace]
    var activeWorkspaceID: UUID?

    static let empty = WorkspaceIndex(workspaces: [], activeWorkspaceID: nil)
}
