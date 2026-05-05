import Foundation

/// W3C Web Annotation TextQuoteSelector — survives DOM regenerations as long
/// as the quoted text still appears in the document.
struct TextAnchor: Codable, Hashable {
    var exact: String
    var prefix: String
    var suffix: String
}

enum CommentAnchor: Codable, Hashable {
    case browser(filePath: String, textAnchor: TextAnchor, fallbackSelector: String, snippet: String)
    case markdown(filePath: String, textAnchor: TextAnchor, fallbackBlockID: String, snippet: String)
    case code(filePath: String, lineStart: Int, lineEnd: Int, snippet: String, lineHash: String)
    case freeform
}

extension CommentAnchor {
    var filePath: String? {
        switch self {
        case .browser(let p, _, _, _), .markdown(let p, _, _, _), .code(let p, _, _, _, _): return p
        case .freeform: return nil
        }
    }

    var snippet: String {
        switch self {
        case .browser(_, _, _, let s), .markdown(_, _, _, let s), .code(_, _, _, let s, _): return s
        case .freeform: return ""
        }
    }

    var iconName: String {
        switch self {
        case .browser:  return "globe"
        case .markdown: return "doc.text"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        case .freeform: return "text.bubble"
        }
    }

    /// Short label for the row subtitle, e.g. "README.md" or "App.swift:42-58".
    var shortLocator: String {
        switch self {
        case .browser(let p, _, _, _), .markdown(let p, _, _, _):
            return (p as NSString).lastPathComponent
        case .code(let p, let start, let end, _, _):
            let name = (p as NSString).lastPathComponent
            return start == end ? "\(name):\(start)" : "\(name):\(start)-\(end)"
        case .freeform:
            return ""
        }
    }
}

enum CommentState: String, Codable {
    case queued      // waiting for the agent to be free
    case working     // shipped in the current batch, agent is processing
    case resolved    // the batch's `result` arrived without error
    case cancelled   // user hit Stop All; needs explicit requeue
    case orphaned    // anchor lost (file deleted / text not found on dispatch)
}

struct Comment: Codable, Identifiable, Hashable {
    var id: UUID
    var anchor: CommentAnchor
    var note: String
    var createdAt: Date
    var state: CommentState
    /// Set when an error/rate-limit pushed this row back to `queued`.
    /// Cleared the next time the row dispatches successfully.
    var errorReason: String?
    /// Absolute file paths of images the user attached. Sent to Claude as
    /// proper image content blocks at dispatch time.
    var attachmentPaths: [String]

    init(
        id: UUID = UUID(),
        anchor: CommentAnchor,
        note: String,
        createdAt: Date = .now,
        state: CommentState = .queued,
        errorReason: String? = nil,
        attachmentPaths: [String] = []
    ) {
        self.id = id
        self.anchor = anchor
        self.note = note
        self.createdAt = createdAt
        self.state = state
        self.errorReason = errorReason
        self.attachmentPaths = attachmentPaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.anchor = try c.decode(CommentAnchor.self, forKey: .anchor)
        self.note = try c.decode(String.self, forKey: .note)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.state = try c.decode(CommentState.self, forKey: .state)
        self.errorReason = try c.decodeIfPresent(String.self, forKey: .errorReason)
        self.attachmentPaths = (try? c.decode([String].self, forKey: .attachmentPaths)) ?? []
    }
}
