import SwiftUI

enum BVRadius {
    static let chip:    CGFloat = 8    // small tags / inline pills
    static let control: CGFloat = 12   // inputs, small cards, sub-rows
    static let card:    CGFloat = 16   // primary cards, list rows, magic box
    static let sheet:   CGFloat = 20   // popovers, drawers, modals
    static let pill:    CGFloat = 999  // fully rounded — buttons, chips
}

/// iOS-smoothing rounded rect — rounder, softer corners than the default.
extension RoundedRectangle {
    static func bv(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// Convenience for clipping with iOS smoothing.
extension View {
    func bvRoundedClip(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
