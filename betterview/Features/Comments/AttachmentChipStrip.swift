import SwiftUI
import AppKit

/// Horizontal strip of small image thumbnails. Used both as the staged
/// attachment chip strip in input boxes and as the inline thumbnail row in
/// user message bubbles.
struct AttachmentChipStrip: View {
    let attachments: [URL]
    var onRemove: ((URL) -> Void)? = nil
    var thumbSize: CGFloat = 44

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments, id: \.self) { url in
                    chip(for: url)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chip(for url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            ThumbnailImage(url: url, side: thumbSize)
                .frame(width: thumbSize, height: thumbSize)
                .background(Color.bvSurface)
                .bvRoundedClip(BVRadius.control)
                .overlay(
                    RoundedRectangle.bv(BVRadius.control)
                        .strokeBorder(Color.bvBorder, lineWidth: 1)
                )
            if let onRemove {
                Button {
                    onRemove(url)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .background(Circle().fill(.white).frame(width: 10, height: 10))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
            }
        }
        .help(url.lastPathComponent)
    }
}

private struct ThumbnailImage: View {
    let url: URL
    let side: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: side * 0.45))
                    .foregroundStyle(Color.bvMuted)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        let url = self.url
        let img = await Task.detached(priority: .utility) { () -> NSImage? in
            NSImage(contentsOf: url)
        }.value
        self.image = img
    }
}
