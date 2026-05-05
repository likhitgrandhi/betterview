import SwiftUI

struct MarkdownPreview: View {
    var text: String? = nil
    var url: URL? = nil
    var commentMode: Bool = false

    @Environment(AppEnvironment.self) private var env
    @State private var loaded: String = ""
    @State private var draft: PendingMarkdownDraft?

    var body: some View {
        let body = url != nil ? loaded : (text ?? "")
        ZStack(alignment: .topLeading) {
            if body.isEmpty {
                ZStack {
                    Color.bvBase
                    Text("Markdown will render here.")
                        .font(BVFont.inter(12))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                }
            } else {
                MarkdownWebView(
                    markdown: body,
                    commentMode: commentMode,
                    pins: pins,
                    onClick: handleClick
                )
                .background(Color.bvBase)
            }

            if let draft {
                InlineCommentPopover(
                    snippet: draft.snippet,
                    onCommit: { note in commit(note: note, draft: draft) },
                    onCancel: { self.draft = nil }
                )
                .offset(x: max(0, draft.rect.minX), y: max(0, draft.rect.maxY + 6))
                .transition(.opacity)
            }
        }
        .task(id: url) {
            await loadIfNeeded()
            guard let url else { return }
            for await _ in debouncedFileChangeStream(url) {
                await loadIfNeeded()
            }
        }
    }

    private var pins: [PinPayload] {
        guard let id = env.selectedItemID,
              let item = env.item(by: id),
              let path = url?.path else { return [] }
        return PinPayload.payloads(for: item.pendingComments, filePath: path, mode: .markdown)
    }

    private func handleClick(_ click: CommentBridge.Click) {
        guard url != nil else { return }
        guard case .markdown = click.anchor else { return }
        draft = PendingMarkdownDraft(rect: click.rect, snippet: click.snippet, anchor: click.anchor)
    }

    private func commit(note: String, draft: PendingMarkdownDraft) {
        guard let path = url?.path,
              let id = env.selectedItemID,
              let vm = env.viewModel(for: id) else {
            self.draft = nil
            return
        }
        guard case let .markdown(blockID, exact, prefix, suffix) = draft.anchor else {
            self.draft = nil
            return
        }
        let text = TextAnchor(exact: exact, prefix: prefix, suffix: suffix)
        let comment = Comment(
            anchor: .markdown(
                filePath: path,
                textAnchor: text,
                fallbackBlockID: blockID ?? "",
                snippet: draft.snippet
            ),
            note: note
        )
        vm.enqueue(comment)
        self.draft = nil
    }

    private func loadIfNeeded() async {
        guard let url else { return }
        // Detach the disk read so a large markdown file doesn't block main.
        let s = await Task.detached(priority: .userInitiated) { () -> String in
            let data = (try? Data(contentsOf: url)) ?? Data()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
        loaded = s
    }
}

private struct PendingMarkdownDraft: Identifiable, Equatable {
    let id = UUID()
    let rect: CGRect
    let snippet: String
    let anchor: CommentBridge.ClickAnchor

    static func == (lhs: PendingMarkdownDraft, rhs: PendingMarkdownDraft) -> Bool {
        lhs.id == rhs.id
    }
}
