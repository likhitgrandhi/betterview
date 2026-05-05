import Foundation

enum BVModel: String, CaseIterable, Identifiable {
    case sonnet
    case opus
    case haiku

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sonnet: "Sonnet"
        case .opus:   "Opus"
        case .haiku:  "Haiku"
        }
    }

    static func label(for raw: String) -> String {
        BVModel(rawValue: raw)?.label ?? raw
    }
}
