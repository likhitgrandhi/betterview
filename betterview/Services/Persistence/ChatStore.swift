import Foundation

/// Persistence for `Item` records. Filename + on-disk paths preserved
/// (the directory is still `chats/` for backwards compatibility) — only the
/// in-memory type changed from Chat to Item.
actor ChatStore {
    func items(in workspaceID: UUID) -> [Item] {
        let dir = AppPaths.chatsDir(for: workspaceID)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let items: [Item] = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let item = try? JSONDecoder.iso.decode(Item.self, from: data)
                else { return nil }
                return item
            }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ item: Item) throws {
        let url = AppPaths.chatFile(workspaceID: item.workspaceID, chatID: item.id)
        let data = try JSONEncoder.iso.encode(item)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    func delete(workspaceID: UUID, itemID: UUID) {
        let url = AppPaths.chatFile(workspaceID: workspaceID, chatID: itemID)
        try? FileManager.default.removeItem(at: url)
    }
}
