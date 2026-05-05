import SwiftUI

/// Compact stand-in for a long assistant artifact in the conversation rail.
/// The artifact *body* lives in the canvas; this is the conversation log
/// entry. We still render the *process* (thinking + tool calls + cost)
/// alongside the compact pill so the rail stays informative.
struct ArtifactCard: View {
    let message: ChatMessage
    let isCanvasArtifact: Bool
    var itemID: UUID? = nil
    var onTap: (() -> Void)? = nil

    @State private var thinkingExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let thinking = message.thinkingText, !thinking.isEmpty {
                thinkingBlock(thinking)
            }
            ForEach(message.toolCalls) { tool in
                ToolCallView(tool: tool, pinTargetItemID: itemID)
            }
            artifactPill
            if let cost = message.costUSD, let dur = message.durationMs {
                Text(String(format: "$%.4f · %d ms", cost, dur))
                    .font(BVFont.inter(11))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvDim)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var artifactPill: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.bvText)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(BVFont.inter(13, weight: .medium))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvText)
                        .lineLimit(1)
                    Text(metaLine)
                        .font(BVFont.inter(11))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                }
                Spacer(minLength: 8)
                if isCanvasArtifact {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("In canvas")
                            .font(BVFont.inter(11))
                            .tracking(0.05)
                    }
                    .foregroundStyle(Color.bvAccent)
                } else {
                    Text("Open in canvas")
                        .font(BVFont.inter(11))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle.bv(BVRadius.control)
                    .fill(Color.bvBase)
                    .overlay(
                        RoundedRectangle.bv(BVRadius.control)
                            .strokeBorder(
                                isCanvasArtifact ? Color.bvAccent.opacity(0.35) : Color.bvBorder,
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func thinkingBlock(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    thinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.bvMuted)
                    Text("Thinking")
                        .font(BVFont.inter(13))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                    Image(systemName: thinkingExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.bvMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if thinkingExpanded {
                Text(thinking)
                    .font(BVFont.inter(13))
                    .tracking(0.05)
                    .lineSpacing(3)
                    .foregroundStyle(Color.bvMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 22)
                    .textSelection(.enabled)
            }
        }
    }

    private var displayTitle: String {
        let lines = message.text.split(whereSeparator: \.isNewline)
        if let heading = lines.first(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }) {
            return String(heading.drop(while: { $0 == "#" || $0 == " " }))
                .trimmingCharacters(in: .whitespaces)
        }
        if let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return String(first).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "**", with: "")
        }
        return "Draft"
    }

    private var metaLine: String {
        let chars = message.text.count
        if chars >= 1000 {
            return String(format: "%.1fk chars", Double(chars) / 1000)
        }
        return "\(chars) chars"
    }
}
