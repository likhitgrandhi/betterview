import SwiftUI

enum BVPreferenceKey {
    static let developerMode = "developerMode"
    static let appearance    = "appearance"
}

enum BVAppearance: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .dark:   "Dark"
        case .light:  "Light"
        }
    }
    var preferred: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }
}
