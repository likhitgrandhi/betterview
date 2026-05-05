import SwiftUI
import AppKit

/// Light frosted sidebar — NSVisualEffectView with a tint overlay so the
/// sidebar is opaque and reads cleanly in the light theme.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    /// Solid sidebar background — opaque F2F2F3 fill on top of a sidebar
    /// material so the column reads as a single calm surface.
    func solidSidebar() -> some View {
        background(
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                Color.bvSurface
            }
        )
    }
}
