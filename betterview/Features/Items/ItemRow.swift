import SwiftUI

struct ItemRow: View {
    let item: Item
    let workspaceName: String?
    let isSelected: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(item.state.dotColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: item.type.defaultIconName)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bvMuted)
                        Text(item.title)
                            .font(BVFont.inter(13, weight: .medium))
                            .tracking(0.05)
                            .foregroundStyle(Color.bvText)
                            .lineLimit(1)
                    }
                    if !item.lastMessagePreview.isEmpty {
                        Text(item.lastMessagePreview)
                            .font(BVFont.inter(13))
                            .tracking(0.05)
                            .foregroundStyle(Color.bvMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let workspaceName, !workspaceName.isEmpty {
                    Text(workspaceName)
                        .font(BVFont.inter(11))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                }
                Text(timestamp)
                    .font(BVFont.inter(11))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvDim)
                    .frame(width: 40, alignment: .trailing)
                    .monospacedDigit()

                Group {
                    if hovering {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.bvMuted)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle.bv(BVRadius.pill)
                                        .fill(Color.bvSurface)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Delete item")
                        .transition(.opacity)
                    } else {
                        Color.clear.frame(width: 24, height: 24)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle.bv(BVRadius.card)
                    .fill(rowFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var rowFill: Color {
        if isSelected { return Color.bvSubtle }
        if hovering { return Color.bvSurface }
        return .clear
    }

    private var timestamp: String {
        let interval = Date().timeIntervalSince(item.updatedAt)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        let days = Int(interval / 86400)
        if days < 7 { return "\(days)d" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: item.updatedAt)
    }
}
