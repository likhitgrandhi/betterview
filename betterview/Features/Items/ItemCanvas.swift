import SwiftUI

/// The "artifact" surface for an item. Resolution order:
///   1. User-pinned file (`env.canvasArtifact[itemID]`)
///   2. User-pinned message (`env.canvasMessage[itemID]`)
///   3. Auto: latest file produced by any tool call
///   4. Auto: latest *substantial* assistant message rendered as markdown
///   5. Empty state
///
/// Short conversational replies leave the canvas alone — they only show in
/// the rail. This is part of the "no duplication, different presentations"
/// rule (Option B).
struct ItemCanvas: View {
    let item: Item
    @Environment(AppEnvironment.self) private var env
    @State private var commentMode: Bool = false

    enum Source {
        case file(URL)
        case message(text: String, messageID: UUID)
        case empty
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch source {
                case .file(let url):
                    renderer(for: url)
                case .message(let text, _):
                    // Reading view of an assistant reply. No commenting hooks
                    // because there's no filePath to anchor against.
                    MarkdownWebView(markdown: text)
                case .empty:
                    empty(icon: "doc.text", text: "Claude's output will appear here.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if case .file(let url) = source, supportsComments(url) {
                commentModeButton
                    .padding(.top, 10)
                    .padding(.trailing, 12)
            }
        }
        .background(Color.bvBase)
    }

    private var commentModeButton: some View {
        Button {
            commentMode.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: commentMode ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 10))
                Text(commentMode ? "Commenting" : "Comment")
                    .font(BVFont.inter(11, weight: commentMode ? .medium : .regular))
                    .tracking(0.05)
            }
            .foregroundStyle(commentMode ? .white : Color.bvText.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(commentMode ? Color.bvAccent : Color.bvSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(commentMode ? Color.bvAccent : Color.bvBorder, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("c", modifiers: [])
        .help("Comment mode (C) — click an element to leave a comment")
    }

    private func supportsComments(_ url: URL) -> Bool {
        switch FileTypes.kind(for: url) {
        case .markdown, .html, .code: return true
        default: return false
        }
    }

    /// Resolves what the canvas should render right now.
    private var source: Source {
        // 1. Explicit file pin (e.g. tool-card click).
        if let pinned = env.canvasArtifact[item.id] {
            return .file(pinned)
        }
        // 2. Explicit message pin (e.g. ArtifactCard click in the rail).
        if let pinnedMessageID = env.canvasMessage[item.id],
           let msg = item.messages.first(where: { $0.id == pinnedMessageID }),
           !msg.text.isEmpty {
            return .message(text: msg.text, messageID: msg.id)
        }
        // 3. Auto: latest file produced by tools.
        if let url = latestProducedFile {
            return .file(url)
        }
        // 4. Auto: latest *substantial* assistant message.
        if let msg = latestSubstantialAssistantMessage {
            return .message(text: msg.text, messageID: msg.id)
        }
        return .empty
    }

    private var latestProducedFile: URL? {
        for message in item.messages.reversed() {
            for tool in message.toolCalls.reversed() where tool.producedFile != nil {
                return tool.producedFile
            }
        }
        return nil
    }

    private var latestSubstantialAssistantMessage: ChatMessage? {
        item.messages.last { $0.role == .assistant && $0.isLongArtifact }
    }

    @ViewBuilder
    private func renderer(for url: URL) -> some View {
        switch FileTypes.kind(for: url) {
        case .markdown:
            MarkdownPreview(url: url, commentMode: commentMode)
        case .image:
            ImagePreview(fixedURL: url)
        case .html:
            BrowserPreview(initialURL: url, commentMode: commentMode)
        case .code, .unsupported, .directory:
            CodePreview(url: url, commentMode: commentMode)
        }
    }

    private func empty(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.bvMuted.opacity(0.6))
            Text(text)
                .font(BVFont.inter(12))
                .tracking(0.05)
                .foregroundStyle(Color.bvMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
