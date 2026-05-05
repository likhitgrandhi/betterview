import Foundation

actor WorkspaceStore {
    private let url: URL

    init(url: URL = AppPaths.workspacesIndex) {
        self.url = url
    }

    func loadIndex() -> WorkspaceIndex {
        guard let data = try? Data(contentsOf: url),
              let idx = try? JSONDecoder.iso.decode(WorkspaceIndex.self, from: data)
        else { return .empty }
        return idx
    }

    func save(_ index: WorkspaceIndex) throws {
        let data = try JSONEncoder.iso.encode(index)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    /// Boots the index, ensuring a Scratch workspace exists and there is an active workspace.
    func bootstrapped() throws -> WorkspaceIndex {
        var idx = loadIndex()
        if !idx.workspaces.contains(where: { $0.isScratch }) {
            let scratch = Workspace(
                name: "Scratch",
                folderURL: AppPaths.scratchFolder,
                isScratch: true
            )
            idx.workspaces.insert(scratch, at: 0)
            if idx.activeWorkspaceID == nil {
                idx.activeWorkspaceID = scratch.id
            }
            try save(idx)
        } else if idx.activeWorkspaceID == nil {
            idx.activeWorkspaceID = idx.workspaces.first?.id
            try save(idx)
        }
        return idx
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
