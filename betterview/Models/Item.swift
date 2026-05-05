import Foundation

/// A unit of AI work. Replaces the old Chat type. On-disk JSON is backwards
/// compatible: missing fields are defaulted so existing chat files load fine.
struct Item: Codable, Identifiable, Hashable {
    var id: UUID
    var workspaceID: UUID
    var title: String
    var claudeSessionID: String?
    var model: String
    var type: ItemType
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var facts: [String]
    /// Pending queue: rows in `queued`, `working`, `cancelled`, or `orphaned` states.
    /// Resolved batches drop out of here entirely; their record lives on the
    /// transcript message's `attachedComments`.
    var pendingComments: [Comment]
    /// ID of the latest assistant message the user has acknowledged (by
    /// opening the chat detail). Drives the `awaitingYou` ↔ `history`
    /// transition — replaces the old time-based heuristic.
    var lastSeenAssistantMessageID: UUID?

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        title: String = "New Item",
        claudeSessionID: String? = nil,
        model: String = "sonnet",
        type: ItemType = .mixed,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [ChatMessage] = [],
        facts: [String] = [],
        pendingComments: [Comment] = [],
        lastSeenAssistantMessageID: UUID? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.claudeSessionID = claudeSessionID
        self.model = model
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.facts = facts
        self.pendingComments = pendingComments
        self.lastSeenAssistantMessageID = lastSeenAssistantMessageID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.workspaceID = try c.decode(UUID.self, forKey: .workspaceID)
        self.title = (try? c.decode(String.self, forKey: .title)) ?? "New Item"
        self.claudeSessionID = try c.decodeIfPresent(String.self, forKey: .claudeSessionID)
        self.model = (try? c.decode(String.self, forKey: .model)) ?? "sonnet"
        self.type = (try? c.decode(ItemType.self, forKey: .type)) ?? .mixed
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? .now
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? .now
        self.messages = (try? c.decode([ChatMessage].self, forKey: .messages)) ?? []
        self.facts = (try? c.decode([String].self, forKey: .facts)) ?? []
        self.pendingComments = (try? c.decode([Comment].self, forKey: .pendingComments)) ?? []
        self.lastSeenAssistantMessageID = try c.decodeIfPresent(UUID.self, forKey: .lastSeenAssistantMessageID)
    }

    var lastMessagePreview: String {
        guard let last = messages.last else { return "" }
        let oneLine = last.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(oneLine.prefix(120))
    }

    /// Computed state — derived from messages + seen marker. Never stored.
    var state: ItemState {
        guard let last = messages.last else { return .drafting }
        if last.isStreaming { return .running }
        if last.role == .user { return .drafting }
        // Last message is assistant. If the user has seen this exact message,
        // it's history; otherwise it's awaiting their review.
        if let latestAssistantID = latestAssistantMessageID,
           lastSeenAssistantMessageID == latestAssistantID {
            return .history
        }
        return .awaitingYou
    }

    /// ID of the most recent non-streaming assistant message, if any.
    var latestAssistantMessageID: UUID? {
        for msg in messages.reversed() where msg.role == .assistant && !msg.isStreaming {
            return msg.id
        }
        return nil
    }
}
