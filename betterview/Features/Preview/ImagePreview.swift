import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImagePreview: View {
    var fixedURL: URL? = nil
    var workspaceFolder: URL? = nil

    @State private var pickedURL: URL?
    @State private var loadedImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            if fixedURL == nil {
                HStack(spacing: 8) {
                    Button("Pick Image…") { pickFile() }
                        .font(BVFont.inter(11))
                        .foregroundStyle(Color.bvText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.bvBorder, lineWidth: 1)
                        )
                        .buttonStyle(.plain)
                    if let pickedURL {
                        Text(pickedURL.lastPathComponent)
                            .font(BVFont.inter(11))
                            .foregroundStyle(Color.bvMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                BVDivider()
            }

            ZStack {
                Color.bvBase
                if let img = currentImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else {
                    Text("Pick a png, jpg or gif file from the workspace.")
                        .font(BVFont.inter(12))
                        .foregroundStyle(Color.bvMuted)
                        .multilineTextAlignment(.center)
                        .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: fixedURL) {
            if let url = fixedURL {
                loadedImage = NSImage(contentsOf: url)
                pickedURL = url
            }
        }
    }

    private var currentImage: NSImage? { loadedImage }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
        if let workspaceFolder { panel.directoryURL = workspaceFolder }
        if panel.runModal() == .OK, let url = panel.url {
            pickedURL = url
            loadedImage = NSImage(contentsOf: url)
        }
    }
}
