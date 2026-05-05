import SwiftUI

struct MessageListView: View {
    let messages: [ChatMessage]
    var emptyHint: String? = nil
    var itemID: UUID? = nil

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { msg in
                            row(for: msg)
                                .id(msg.id)
                        }
                    }
                }
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(Color.bvBase)
            .onChange(of: messages.last?.id) { _, newID in
                guard let newID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newID, anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.text.count ?? 0) { _, _ in
                if let id = messages.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    /// Substantial finished assistant replies render compactly so the rail is
    /// a log of turns instead of duplicating prose that's already in the canvas.
    @ViewBuilder
    private func row(for msg: ChatMessage) -> some View {
        if msg.isLongArtifact, let itemID {
            ArtifactCard(
                message: msg,
                isCanvasArtifact: msg.id == canvasMessageID,
                itemID: itemID,
                onTap: {
                    if env.canvasMessage[itemID] == msg.id {
                        env.pinCanvasMessage(nil, for: itemID)
                    } else {
                        env.pinCanvasMessage(msg.id, for: itemID)
                    }
                }
            )
        } else {
            MessageBubble(message: msg, itemID: itemID)
        }
    }

    private var canvasMessageID: UUID? {
        guard let itemID else { return nil }
        if let pinned = env.canvasMessage[itemID] { return pinned }
        if env.canvasArtifact[itemID] != nil { return nil }
        for msg in messages.reversed() {
            for tool in msg.toolCalls.reversed() where tool.producedFile != nil {
                return nil
            }
        }
        return messages.last(where: { $0.role == .assistant && $0.isLongArtifact })?.id
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = emptyHint {
                Text(hint)
                    .font(BVFont.inter(13))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvMuted)
            } else {
                Text("Start a conversation.")
                    .font(BVFont.inter(13))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }
}
