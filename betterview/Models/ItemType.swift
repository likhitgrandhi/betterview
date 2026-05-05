import Foundation

enum ItemType: String, Codable, Hashable {
    case mixed       // chat-style; default for newly created items
    case document    // markdown / prose
    case image       // screenshot / generated graphic
    case code        // code file / diff
    case log         // watcher activity stream

    var defaultIconName: String {
        switch self {
        case .mixed:    return "bubble.left.and.bubble.right"
        case .document: return "doc.text"
        case .image:    return "photo"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        case .log:      return "waveform"
        }
    }
}
