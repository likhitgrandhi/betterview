import Foundation

struct ChatMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    var id: UUID
    var role: Role
    var text: String
    var thinkingText: String?
    var toolCalls: [ToolCall]
    var timestamp: Date
    var isStreaming: Bool
    var costUSD: Double?
    var durationMs: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    /// Snapshot of the queued comments that shipped with this user turn.
    /// Empty for assistant/system messages and for free-text user turns.
    var attachedComments: [Comment]

    init(
        id: UUID = UUID(),
        role: Role,
        text: String = "",
        thinkingText: String? = nil,
        toolCalls: [ToolCall] = [],
        timestamp: Date = .now,
        isStreaming: Bool = false,
        costUSD: Double? = nil,
        durationMs: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        attachedComments: [Comment] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.thinkingText = thinkingText
        self.toolCalls = toolCalls
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.costUSD = costUSD
        self.durationMs = durationMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.attachedComments = attachedComments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.role = try c.decode(Role.self, forKey: .role)
        self.text = (try? c.decode(String.self, forKey: .text)) ?? ""
        self.thinkingText = try c.decodeIfPresent(String.self, forKey: .thinkingText)
        self.toolCalls = (try? c.decode([ToolCall].self, forKey: .toolCalls)) ?? []
        self.timestamp = (try? c.decode(Date.self, forKey: .timestamp)) ?? .now
        self.isStreaming = (try? c.decode(Bool.self, forKey: .isStreaming)) ?? false
        self.costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD)
        self.durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        self.inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens)
        self.outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens)
        self.attachedComments = (try? c.decode([Comment].self, forKey: .attachedComments)) ?? []
    }

    /// Heuristic: this assistant turn produced a long-form artifact, not a
    /// short conversational reply or a clarifying question. Used by the rail
    /// to render a compact card instead of duplicating the canvas content.
    ///
    /// Discriminator vs. clarifying: it's not *whether* the message has a `?`
    /// (most assistant replies end with "want me to refine?") — it's *where*.
    /// Clarifying messages ask up front; finished artifacts add a courtesy
    /// question only at the very end.
    var isLongArtifact: Bool {
        guard role == .assistant, !isStreaming else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // 1. Structured content always wins.
        if trimmed.contains("\n## ") || trimmed.contains("\n# ") { return true }
        if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") { return true }
        if trimmed.contains("```") { return true }

        // 2. Long body always wins. A trailing courtesy question doesn't change
        //    that an artifact was produced; clarifying messages don't reach
        //    this length.
        if trimmed.count >= 1000 { return true }

        // 3. Medium-length (600–999 chars): only an artifact if the message
        //    isn't *primarily* asking. A `?` in the opening 160 chars means
        //    the assistant is asking for clarification before producing.
        let opening = String(trimmed.prefix(160))
        if opening.contains("?") { return false }

        return trimmed.count >= 600
    }
}
