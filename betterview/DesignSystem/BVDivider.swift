import SwiftUI

struct BVDivider: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal

    var body: some View {
        switch axis {
        case .horizontal:
            Rectangle()
                .fill(Color.bvBorder)
                .frame(maxWidth: .infinity)
                .frame(height: 1)
        case .vertical:
            Rectangle()
                .fill(Color.bvBorder)
                .frame(maxHeight: .infinity)
                .frame(width: 1)
        }
    }
}
