import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    var itemID: UUID? = nil
    @State private var thinkingExpanded = false

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userBubble
            case .assistant:
                assistantContent
            case .system:
                systemContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var userBubble: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 32)
            VStack(alignment: .leading, spacing: 8) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(BVFont.inter(13))
                        .tracking(0.05)
                        .lineSpacing(3)
                        .foregroundStyle(Color.bvText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !attachedImageURLs.isEmpty {
                    AttachmentChipStrip(attachments: attachedImageURLs, thumbSize: 56)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle.bv(BVRadius.card)
                    .fill(Color.bvSurface)
            )
        }
    }

    private var attachedImageURLs: [URL] {
        message.attachedComments
            .flatMap(\.attachmentPaths)
            .map { URL(fileURLWithPath: $0) }
    }

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let thinking = message.thinkingText, !thinking.isEmpty {
                thinkingBlock(thinking)
            }

            ForEach(message.toolCalls) { tool in
                ToolCallView(tool: tool, pinTargetItemID: itemID)
            }

            if !message.text.isEmpty {
                renderedText
            }

            if message.isStreaming {
                HStack(spacing: 8) {
                    DotMatrixLoader()
                    Text("Working…")
                        .font(BVFont.inter(13))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                }
                .padding(.top, 2)
            }

            if let cost = message.costUSD, let dur = message.durationMs {
                Text(String(format: "$%.4f · %d ms", cost, dur))
                    .font(BVFont.inter(11))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvDim)
                    .padding(.top, 2)
            }
        }
    }

    private var systemContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.bvMuted)
                .padding(.top, 3)
            Text(message.text)
                .font(BVFont.inter(13))
                .tracking(0.05)
                .foregroundStyle(Color.bvMuted)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle.bv(BVRadius.control)
                .fill(Color.bvSurface)
        )
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
                    Text(message.isStreaming && (message.text.isEmpty) ? "Thinking…" : "Thinking")
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

    @ViewBuilder
    private var renderedText: some View {
        let text = message.text
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(BVFont.inter(13))
                .tracking(0.05)
                .lineSpacing(4)
                .foregroundStyle(Color.bvText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .font(BVFont.inter(13))
                .tracking(0.05)
                .lineSpacing(4)
                .foregroundStyle(Color.bvText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
