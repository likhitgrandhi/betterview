import CoreFoundation

enum BVSpacing {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 6
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 28
}

/// Minimum hit-target heights enforced across the app.
enum BVMetrics {
    /// Sidebar menu rows (workspace, scope, etc).
    static let sidebarRow:  CGFloat = 36
    /// Standard control height (buttons, chips, pickers).
    static let control:     CGFloat = 32
    /// Compact controls (small inline buttons, small chips).
    static let controlSm:   CGFloat = 24
}
