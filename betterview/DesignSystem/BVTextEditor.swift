import SwiftUI
import AppKit

/// Multi-line text editor where plain Enter sends, and Cmd/Shift+Enter inserts a newline.
/// Cmd+V detects pasted images, writes them to a temp file, and forwards the
/// URLs via `onPasteImages` (so the composer can stage them as attachments).
struct BVTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var font: NSFont
    var textColor: NSColor
    var minHeight: CGFloat = 28
    /// Called when the user pastes one or more images. URLs point to temp files.
    var onPasteImages: (([URL]) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = BVTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.string = text
        textView.onSubmit = onSubmit
        textView.onPasteImages = onPasteImages
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.allowsCharacterPickerTouchBarItem = false

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? BVTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onSubmit = onSubmit
        textView.onPasteImages = onPasteImages
        context.coordinator.onSubmit = onSubmit
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

final class BVTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onPasteImages: (([URL]) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.contains(.command) || mods.contains(.shift) || mods.contains(.option) {
                super.keyDown(with: event)
            } else {
                onSubmit?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let urls = imagesFromPasteboard(pb), !urls.isEmpty {
            onPasteImages?(urls)
            return
        }
        super.paste(sender)
    }

    /// If the pasteboard contains image data (screenshots, copied photos), write
    /// each image to a temp PNG and return the URLs. Returns nil if no images.
    private func imagesFromPasteboard(_ pb: NSPasteboard) -> [URL]? {
        // First try file URLs that point to image files (Finder copy).
        if let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let imageURLs = fileURLs.filter { url in
                guard url.isFileURL else { return false }
                let ext = url.pathExtension.lowercased()
                return ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"].contains(ext)
            }
            if !imageURLs.isEmpty { return imageURLs }
        }

        // Then try raw image objects (screenshot in clipboard, etc.).
        guard let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              !images.isEmpty
        else { return nil }

        var urls: [URL] = []
        for image in images {
            if let url = writeTempPNG(from: image) {
                urls.append(url)
            }
        }
        return urls.isEmpty ? nil : urls
    }

    private func writeTempPNG(from image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("betterview-paste-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
