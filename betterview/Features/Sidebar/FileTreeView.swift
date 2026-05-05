import SwiftUI
import AppKit

struct FileTreeView: View {
    let root: URL
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(FileNode.loadChildren(of: root)) { child in
                    FileTreeRow(node: child, depth: 0)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden)
    }
}

struct FileTreeRow: View {
    let node: FileNode
    let depth: Int
    @Environment(AppEnvironment.self) private var env
    @State private var isExpanded = false
    @State private var children: [FileNode] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if node.isDirectory && isExpanded {
                ForEach(children) { child in
                    FileTreeRow(node: child, depth: depth + 1)
                }
            }
        }
    }

    private var row: some View {
        let isPreviewed = env.previewedFile?.url == node.url
        return HStack(spacing: 4) {
            // Indent
            if depth > 0 {
                Color.clear.frame(width: CGFloat(depth) * 12)
            }

            // Disclosure chevron (only for directories)
            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.bvMuted)
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10)
            }

            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundStyle(node.isOpenable || node.isDirectory ? Color.bvMuted : Color.bvMuted.opacity(0.4))
                .frame(width: 12)

            Text(node.name)
                .font(BVFont.inter(11))
                .tracking(0.1)
                .foregroundStyle(rowForeground)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isPreviewed ? Color.bvSubtle : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { activate() }
        .onTapGesture(count: 1) {
            if node.isDirectory { toggle() }
        }
        .help(node.isOpenable ? "Double-click to preview" : (node.isDirectory ? node.name : "Unsupported file"))
        .opacity(node.isDirectory || node.isOpenable ? 1 : 0.45)
        .allowsHitTesting(node.isDirectory || node.isOpenable)
    }

    private var iconName: String {
        if node.isDirectory { return isExpanded ? "folder" : "folder.fill" }
        switch node.kind {
        case .markdown: return "doc.richtext"
        case .image:    return "photo"
        case .html:     return "globe"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        case .unsupported: return "doc"
        case .directory: return "folder"
        }
    }

    private var rowForeground: Color {
        if node.isDirectory { return Color.bvText.opacity(0.85) }
        return node.isOpenable ? Color.bvText.opacity(0.78) : Color.bvMuted
    }

    private func activate() {
        if node.isDirectory {
            toggle()
        } else if node.isOpenable {
            env.previewedFile = node
        }
    }

    private func toggle() {
        isExpanded.toggle()
        if isExpanded && children.isEmpty {
            children = FileNode.loadChildren(of: node.url)
        }
    }
}
