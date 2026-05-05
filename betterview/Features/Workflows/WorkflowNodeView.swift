import SwiftUI

/// Pure visual content for a workflow node. Drag, selection, hover, and
/// connector handles are all handled by `FlowCanvas` — this view only
/// describes how the card looks for given data + state.
struct WorkflowNodeView: View {
    let node: WorkflowNode
    let isSelected: Bool
    let runState: NodeRunState?

    var body: some View {
        VStack(spacing: 6) {
            statusBadge
            avatar
            VStack(spacing: 2) {
                Text(node.title)
                    .font(BVFont.inter(11, weight: .medium))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvText)
                    .lineLimit(1)
                Text(roleLine)
                    .font(BVFont.inter(9))
                    .tracking(0.05)
                    .foregroundStyle(roleColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: WorkflowFlowAdapter.nodeSize.width,
               height: WorkflowFlowAdapter.nodeSize.height)
        .background(
            RoundedRectangle(cornerRadius: BVRadius.sheet)
                .fill(Color.bvSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: BVRadius.sheet)
                        .strokeBorder(isSelected ? Color.bvAccent : Color.bvBorder,
                                      lineWidth: isSelected ? 1.5 : 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        )
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: node.avatar.colorHex),
                            Color(hex: node.avatar.colorHex).opacity(0.6),
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 30
                    )
                )
            if let symbol = node.avatar.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 32, height: 32)
        .shadow(color: Color(hex: node.avatar.colorHex).opacity(0.4), radius: 5, y: 1)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusLabel)
                .font(BVFont.inter(8, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.bvBase.opacity(0.5)))
    }

    private var statusColor: Color {
        switch runState?.status ?? .idle {
        case .idle:    return Color.bvMuted
        case .running: return Color.bvAccent
        case .done:    return Color(hex: "5DBE9C")
        case .error:   return Color.red
        }
    }

    private var statusLabel: String {
        switch runState?.status ?? .idle {
        case .idle:    return "IDLE"
        case .running: return "RUNNING"
        case .done:    return "DONE"
        case .error:   return "ERROR"
        }
    }

    private var roleLine: String {
        if let s = node.subtitle, !s.isEmpty { return s }
        switch node.kind {
        case .input:  return "Input"
        case .agent:  return "Agent"
        case .output: return "Output"
        }
    }

    private var roleColor: Color {
        switch node.kind {
        case .input:  return Color(hex: "8E7AE0")
        case .agent:  return Color.bvAccent
        case .output: return Color(hex: "5DBE9C")
        }
    }
}
