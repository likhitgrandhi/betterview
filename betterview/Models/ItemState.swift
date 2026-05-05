import SwiftUI

/// State of an item in the list. Computed from the item's data — not stored.
enum ItemState: String, Hashable {
    case running       // a turn is mid-stream right now
    case awaitingYou   // assistant finished, user hasn't seen it yet
    case drafting      // user just composed; not yet sent or fresh
    case history       // user has reviewed the latest assistant turn
    case archived      // user-archived (Phase B)

    var label: String {
        switch self {
        case .running:     return "Running"
        case .awaitingYou: return "Needs review"
        case .drafting:    return "Drafting"
        case .history:     return "History"
        case .archived:    return "Archived"
        }
    }

    var groupTitle: String {
        switch self {
        case .running:     return "RUNNING"
        case .awaitingYou: return "NEEDS REVIEW"
        case .drafting:    return "DRAFTING"
        case .history:     return "HISTORY"
        case .archived:    return "ARCHIVED"
        }
    }

    /// Order in which state sections appear in the list.
    var groupOrder: Int {
        switch self {
        case .awaitingYou: return 0
        case .running:     return 1
        case .drafting:    return 2
        case .history:     return 3
        case .archived:    return 4
        }
    }

    var dotColor: Color {
        switch self {
        case .running:     return .green
        case .awaitingYou: return .orange
        case .drafting:    return .blue
        case .history:     return .gray
        case .archived:    return .gray.opacity(0.5)
        }
    }
}
