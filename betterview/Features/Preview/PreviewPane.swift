import SwiftUI

enum PreviewMode: String, CaseIterable, Identifiable {
    case markdown, browser, image
    var id: String { rawValue }
    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .browser: "Browser"
        case .image: "Image"
        }
    }
    var icon: String {
        switch self {
        case .markdown: "text.alignleft"
        case .browser: "globe"
        case .image: "photo"
        }
    }
}

struct PreviewPane: View {
    @Environment(AppEnvironment.self) private var env
    @State private var mode: PreviewMode = .markdown
    @State private var commentMode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            BVDivider()
            content
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if let file = env.previewedFile {
            HStack(spacing: 6) {
                Image(systemName: fileIcon(for: file))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.bvMuted)
                Text(file.name)
                    .font(BVFont.inter(11, weight: .medium))
                    .tracking(0.1)
                    .foregroundStyle(Color.bvText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if supportsComments(file) {
                    commentModeButton
                }
                Button {
                    env.previewedFile = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.bvMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close file preview")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 2) {
                ForEach(PreviewMode.allCases) { m in
                    Button {
                        mode = m
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: m.icon)
                                .font(.system(size: 10))
                            Text(m.title)
                                .font(BVFont.inter(11, weight: mode == m ? .medium : .regular))
                                .tracking(0.1)
                        }
                        .foregroundStyle(mode == m ? Color.bvText : Color.bvMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(mode == m ? Color.bvSubtle : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let file = env.previewedFile {
            switch file.kind {
            case .markdown:
                MarkdownPreview(url: file.url, commentMode: commentMode)
            case .image:
                ImagePreview(fixedURL: file.url)
            case .html:
                BrowserPreview(initialURL: file.url, commentMode: commentMode)
            case .code:
                CodePreview(url: file.url, commentMode: commentMode)
            case .directory, .unsupported:
                Text("Cannot preview this file type.")
                    .font(BVFont.inter(12))
                    .foregroundStyle(Color.bvMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            switch mode {
            case .markdown:
                MarkdownPreview(text: latestAssistantText)
            case .browser:
                BrowserPreview()
            case .image:
                ImagePreview(workspaceFolder: env.activeWorkspace?.folderURL)
            }
        }
    }

    private var commentModeButton: some View {
        Button {
            commentMode.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: commentMode ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 10))
                Text("Comment")
                    .font(BVFont.inter(11, weight: commentMode ? .medium : .regular))
                    .tracking(0.05)
            }
            .foregroundStyle(commentMode ? Color.bvAccent : Color.bvMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(commentMode ? Color.bvAccent.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("c", modifiers: [])
        .help("Comment mode (C) — click an element to leave a comment")
    }

    private func supportsComments(_ node: FileNode) -> Bool {
        switch node.kind {
        case .code, .markdown, .html: return true
        default: return false
        }
    }

    private func fileIcon(for node: FileNode) -> String {
        switch node.kind {
        case .markdown: "doc.richtext"
        case .image:    "photo"
        case .html:     "globe"
        case .code:     "chevron.left.forwardslash.chevron.right"
        default:        "doc"
        }
    }

    private var latestAssistantText: String {
        guard let id = env.selectedItemID,
              let item = env.item(by: id) else { return "" }
        return item.messages.last { $0.role == .assistant }?.text ?? ""
    }
}
