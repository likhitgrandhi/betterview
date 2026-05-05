import SwiftUI
import CryptoKit

struct CodePreview: View {
    let url: URL
    var commentMode: Bool = false
    @Environment(AppEnvironment.self) private var env

    @State private var content: String = ""
    @State private var lines: [String] = []
    @State private var loadError: String?
    @State private var draft: PendingDraft?
    @State private var hoveringLine: Int?
    @State private var flashPinID: UUID?

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView([.vertical]) {
                if let err = loadError {
                    Text(err)
                        .font(BVFont.inter(12))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(14)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                            lineRow(index: idx + 1, content: line)
                                .id(idx + 1)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: flashPinID) { _, newValue in
                guard let id = newValue, let pin = pins.first(where: { $0.id == id }) else { return }
                withAnimation { scroller.scrollTo(pin.lineStart, anchor: .center) }
            }
        }
        .task(id: url) {
            await load()
            for await _ in debouncedFileChangeStream(url) {
                await load()
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func lineRow(index: Int, content: String) -> some View {
        let pinForLine = pins.first(where: { index >= $0.lineStart && index <= $0.lineEnd })
        let isFirstLineOfPin = pinForLine?.lineStart == index
        let isHovering = (hoveringLine == index) && commentMode

        HStack(alignment: .top, spacing: 0) {
            // Gutter: line number + pin marker
            ZStack(alignment: .topTrailing) {
                Text("\(index)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.bvMuted.opacity(0.7))
                    .frame(width: 44, alignment: .trailing)
                    .padding(.trailing, 8)
                if let pin = pinForLine, isFirstLineOfPin {
                    pinBadge(for: pin)
                        .offset(x: 6, y: -2)
                }
            }

            // Left accent bar — highlights pinned ranges or hover
            Rectangle()
                .fill(accentColor(for: pinForLine, hovering: isHovering))
                .frame(width: 2)
                .padding(.trailing, 8)

            Group {
                if commentMode {
                    Text(content.isEmpty ? " " : content)
                        .textSelection(.disabled)
                } else {
                    Text(content.isEmpty ? " " : content)
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color.bvText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 14)
        }
        .padding(.vertical, 1)
        .background(rowBackground(for: pinForLine, hovering: isHovering))
        .contentShape(Rectangle())
        .onHover { inside in
            if commentMode { hoveringLine = inside ? index : (hoveringLine == index ? nil : hoveringLine) }
        }
        .onTapGesture {
            if commentMode {
                let snippet = String(content.trimmingCharacters(in: .whitespaces).prefix(120))
                draft = PendingDraft(line: index, snippet: snippet)
            } else if let pin = pinForLine {
                flashPinID = pin.id
            }
        }
        .popover(item: bindingForDraft(at: index), arrowEdge: .leading) { _ in
            InlineCommentPopover(
                snippet: draft?.snippet ?? "",
                onCommit: { note in commit(note: note, line: index) },
                onCancel: { draft = nil }
            )
        }
    }

    private func bindingForDraft(at line: Int) -> Binding<PendingDraft?> {
        Binding(
            get: { draft?.line == line ? draft : nil },
            set: { newValue in if newValue == nil { draft = nil } }
        )
    }

    private func rowBackground(for pin: PinRow?, hovering: Bool) -> Color {
        if pin != nil { return Color.bvAccent.opacity(0.08) }
        if hovering { return Color.bvAccent.opacity(0.05) }
        return Color.clear
    }

    private func accentColor(for pin: PinRow?, hovering: Bool) -> Color {
        if let pin {
            switch pin.state {
            case .working: return Color.bvAccent
            case .queued: return Color.bvAccent.opacity(0.55)
            case .cancelled: return .red.opacity(0.6)
            case .orphaned: return .orange.opacity(0.6)
            case .resolved: return Color.bvAccent.opacity(0.3)
            }
        }
        if hovering { return Color.bvAccent.opacity(0.5) }
        return Color.clear
    }

    @ViewBuilder
    private func pinBadge(for pin: PinRow) -> some View {
        Text("\(pin.number)")
            .font(BVFont.inter(9, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(pin.state == .queued ? Color.bvAccent.opacity(0.7) : Color.bvAccent))
    }

    // MARK: - Pin sourcing

    private struct PinRow: Identifiable {
        let id: UUID
        let number: Int
        let lineStart: Int
        let lineEnd: Int
        let state: CommentState
    }

    private var pins: [PinRow] {
        guard let id = env.selectedItemID,
              let item = env.item(by: id) else { return [] }
        let path = url.path
        var result: [PinRow] = []
        var counter = 0
        for c in item.pendingComments {
            guard case .code(let filePath, let start, let end, _, _) = c.anchor, filePath == path else { continue }
            counter += 1
            result.append(PinRow(id: c.id, number: counter, lineStart: start, lineEnd: end, state: c.state))
        }
        return result
    }

    // MARK: - Commit

    private func commit(note: String, line: Int) {
        guard let id = env.selectedItemID,
              let vm = env.viewModel(for: id) else {
            draft = nil
            return
        }
        let snippet = lines.indices.contains(line - 1) ? lines[line - 1] : ""
        let comment = Comment(
            anchor: .code(
                filePath: url.path,
                lineStart: line,
                lineEnd: line,
                snippet: String(snippet.prefix(200)),
                lineHash: sha256(snippet)
            ),
            note: note
        )
        vm.enqueue(comment)
        draft = nil
    }

    private func sha256(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    // MARK: - Load

    private func load() async {
        // Detach the disk read so a multi-MB file doesn't block the main thread.
        let url = self.url
        let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
            do {
                let data = try Data(contentsOf: url)
                return .success(String(data: data, encoding: .utf8) ?? "<binary>")
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let s):
            content = s
            lines = s.components(separatedBy: "\n")
            loadError = nil
        case .failure(let error):
            content = ""
            lines = []
            loadError = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

private struct PendingDraft: Identifiable, Equatable {
    let id = UUID()
    let line: Int
    let snippet: String
}
