import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MagicPromptBox: View {
    @Environment(AppEnvironment.self) private var env
    @State private var draft: String = ""
    @State private var stagedAttachments: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            if !stagedAttachments.isEmpty {
                AttachmentChipStrip(
                    attachments: stagedAttachments,
                    onRemove: { url in stagedAttachments.removeAll { $0 == url } }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("What do you want to work on?")
                        .font(BVFont.inter(13))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
                BVTextEditor(
                    text: $draft,
                    onSubmit: submit,
                    font: NSFont(name: "Inter-Regular", size: 13) ?? .systemFont(ofSize: 13),
                    textColor: NSColor(Color.bvText),
                    onPasteImages: { urls in
                        for url in urls where !stagedAttachments.contains(url) {
                            stagedAttachments.append(url)
                        }
                    }
                )
                .frame(minHeight: 36, maxHeight: 140)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            HStack(spacing: 6) {
                Button {
                    pickAttachments()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.bvMuted)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle.bv(BVRadius.pill)
                                .fill(Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(BVPillButtonStyle())
                .help("Attach an image")
                Spacer()
                Button {
                    submit()
                } label: {
                    HStack(spacing: 6) {
                        Text("Start")
                            .font(BVFont.inter(13, weight: .medium))
                            .tracking(0.05)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(canSend ? .white : Color.bvMuted)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle.bv(BVRadius.pill)
                            .fill(canSend ? Color.bvAccent : Color.bvSubtle)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle.bv(BVRadius.card)
                .fill(Color.bvSurface)
                .overlay(
                    RoundedRectangle.bv(BVRadius.card)
                        .strokeBorder(Color.bvBorder, lineWidth: 1)
                )
        )
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !stagedAttachments.isEmpty
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = stagedAttachments.map(\.path)
        guard !text.isEmpty || !paths.isEmpty else { return }
        draft = ""
        let snapshot = paths
        stagedAttachments = []
        Task { await createAndOpen(prompt: text, attachments: snapshot) }
    }

    private func pickAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Attach images"
        if panel.runModal() == .OK {
            for url in panel.urls {
                if !stagedAttachments.contains(url) { stagedAttachments.append(url) }
            }
        }
    }

    private func createAndOpen(prompt: String, attachments: [String] = []) async {
        let workspaceID: UUID = {
            switch env.listScope {
            case .workspace(let id), .workflows(let id): return id
            case .all:
                if let active = env.activeWorkspaceID { return active }
                if let scratch = env.workspaces.first(where: { $0.isScratch }) { return scratch.id }
                return env.workspaces.first?.id ?? UUID()
            }
        }()
        let item = await env.newItem(in: workspaceID)
        env.openItem(item.id)
        if let vm = env.viewModel(for: item.id) {
            vm.enqueueFreeform(prompt, attachmentPaths: attachments)
        }
    }
}

/// Subtle press feedback for round/circular buttons.
struct BVPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle.bv(BVRadius.pill)
                    .fill(configuration.isPressed ? Color.bvSubtle : Color.clear)
            )
    }
}
