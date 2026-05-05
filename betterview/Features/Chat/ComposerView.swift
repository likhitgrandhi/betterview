import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ComposerView: View {
    @Bindable var viewModel: ItemViewModel
    @State private var draft: String = ""
    @State private var stagedAttachments: [URL] = []
    @AppStorage(BVPreferenceKey.developerMode) private var developerMode = false

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(BVFont.inter(13))
                        .tracking(0.05)
                }
                .foregroundStyle(.red.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }

            QueuePanel(viewModel: viewModel)

            composerBox
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .background(Color.bvBase)
    }

    private var composerBox: some View {
        VStack(spacing: 0) {
            if !stagedAttachments.isEmpty {
                AttachmentChipStrip(
                    attachments: stagedAttachments,
                    onRemove: { url in stagedAttachments.removeAll { $0 == url } }
                )
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(placeholderText)
                        .font(BVFont.inter(13))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
                BVTextEditor(
                    text: $draft,
                    onSubmit: send,
                    font: NSFont(name: "Inter-Regular", size: 13) ?? .systemFont(ofSize: 13),
                    textColor: NSColor(Color.bvText),
                    onPasteImages: { urls in
                        for url in urls where !stagedAttachments.contains(url) {
                            stagedAttachments.append(url)
                        }
                    }
                )
                .frame(minHeight: 24, maxHeight: 120)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)

            HStack(spacing: 4) {
                Button {
                    pickAttachments()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.bvMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BVPillButtonStyle())
                .help("Attach an image")

                if developerMode {
                    Menu {
                        ForEach(BVModel.allCases) { m in
                            Button {
                                Task { await viewModel.setModel(m.rawValue) }
                            } label: {
                                HStack {
                                    Text(m.label)
                                    if viewModel.item.model == m.rawValue {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.bvAccent)
                            Text(BVModel.label(for: viewModel.item.model))
                                .font(BVFont.inter(13))
                                .tracking(0.05)
                                .foregroundStyle(Color.bvText.opacity(0.85))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.bvMuted)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle.bv(BVRadius.pill)
                                .fill(Color.bvSurface)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.leading, 4)
                }

                if !viewModel.statusLine.isEmpty {
                    Text(viewModel.statusLine)
                        .font(BVFont.inter(11))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                        .padding(.leading, 8)
                }

                Spacer()

                Button {
                    send()
                } label: {
                    Image(systemName: viewModel.isAwaitingResponse ? "plus" : "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(canSend ? .white : Color.bvMuted)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle.bv(BVRadius.pill)
                                .fill(canSend ? Color.bvAccent : Color.bvSubtle)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle.bv(BVRadius.sheet)
                .fill(Color.bvSurface)
                .overlay(
                    RoundedRectangle.bv(BVRadius.sheet)
                        .strokeBorder(Color.bvBorder, lineWidth: 1)
                )
        )
    }

    private var placeholderText: String {
        viewModel.isAwaitingResponse
            ? "Add a task — runs when current finishes…"
            : "Type a task — runs immediately, or pin from a preview"
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !stagedAttachments.isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = stagedAttachments.map(\.path)
        guard !text.isEmpty || !paths.isEmpty else { return }
        draft = ""
        stagedAttachments = []
        viewModel.enqueueFreeform(text, attachmentPaths: paths)
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
}
