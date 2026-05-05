import SwiftUI

extension Color {
    // Light, elegant palette.
    // bvBase    — main content area background (white)
    // bvSurface — sidebar / cards / inset surfaces (warm light grey)
    // bvBorder  — hairline borders & dividers
    // bvSubtle  — hover & selected backgrounds
    // bvText    — primary text
    // bvMuted   — secondary text / icons
    // bvAccent  — primary action / brand orange
    // bvChip    — chip / tag background
    // bvDim     — tertiary text (timestamps, hints)
    static let bvBase    = Color(hex: "FFFFFF")
    static let bvSurface = Color(hex: "F2F2F3")
    static let bvBorder  = Color(hex: "ECECEC")
    static let bvSubtle  = Color(hex: "E8E8EA")
    static let bvText    = Color(hex: "1A1A1A")
    static let bvMuted   = Color(hex: "6E6E73")
    static let bvAccent  = Color(hex: "D97757")
    static let bvChip    = Color(hex: "F2F2F3")
    static let bvDim     = Color(hex: "9A9AA0")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
