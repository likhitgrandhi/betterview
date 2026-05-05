import SwiftUI
import AppKit

/// The mini-composer that pops next to a selection on any artifact.
/// Single-line text field; Enter commits, Esc cancels.
struct InlineCommentPopover: View {
    let snippet: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !snippet.isEmpty {
                Text(snippet)
                    .font(BVFont.inter(10))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: 6) {
                TextField("Describe the change", text: $draft)
                    .textFieldStyle(.plain)
                    .font(BVFont.inter(13))
                    .foregroundStyle(Color.bvText)
                    .focused($focused)
                    .onSubmit(commit)
                Button(action: commit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(canCommit ? .white : Color.bvMuted)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(canCommit ? Color.bvAccent : Color.bvSubtle)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)
            }
        }
        .padding(10)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bvSurface)
        )
        .onAppear { focused = true }
        .onExitCommand { onCancel() }
    }

    private var canCommit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
    }
}
