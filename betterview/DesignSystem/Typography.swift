import SwiftUI
import AppKit

enum BVFont {
    nonisolated static func register() {
        for name in ["Inter-Regular", "Inter-Medium"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf",
                                      subdirectory: "Resources/Fonts")
                   ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Only Regular and Medium are exposed; everything heavier is clamped to Medium.
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let postScriptName = (weight == .regular) ? "Inter-Regular" : "Inter-Medium"
        return Font.custom(postScriptName, size: size)
    }
}

extension View {
    func interFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.font(BVFont.inter(size, weight: weight))
            .tracking(0.05)
            .lineSpacing(2)
    }
}
