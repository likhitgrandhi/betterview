import SwiftUI
@preconcurrency import WebKit

struct BrowserPreview: View {
    var initialURL: URL? = URL(string: "https://anthropic.com")
    var commentMode: Bool = false

    @Environment(AppEnvironment.self) private var env
    @State private var addressDraft: String = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webViewBox = WebViewBox()
    @State private var draft: PendingBrowserDraft?

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            BVDivider()
            ZStack(alignment: .topLeading) {
                WebViewRepresentable(
                    box: webViewBox,
                    commentMode: commentMode,
                    pins: pins,
                    onNavigate: { url, back, forward in
                        if let url { self.addressDraft = url.absoluteString }
                        self.canGoBack = back
                        self.canGoForward = forward
                    },
                    onClick: handleClick
                )

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
        }
        .task(id: initialURL) {
            guard let url = initialURL else { return }
            addressDraft = url.absoluteString
            webViewBox.load(url)
            // For local file artifacts, refresh the WKWebView when Claude
            // rewrites the underlying file.
            guard url.isFileURL else { return }
            for await _ in debouncedFileChangeStream(url) {
                webViewBox.load(url)
            }
        }
    }

    private var pins: [PinPayload] {
        guard let id = env.selectedItemID,
              let item = env.item(by: id),
              let path = currentFilePath else { return [] }
        return PinPayload.payloads(for: item.pendingComments, filePath: path, mode: .browser)
    }

    /// Anchors only attach to local file:// URLs (Claude-generated artifacts).
    /// Remote pages won't accumulate persisted pins because their "filePath"
    /// changes every navigation.
    private var currentFilePath: String? {
        if let initial = initialURL, initial.isFileURL { return initial.path }
        if let s = URL(string: addressDraft), s.isFileURL { return s.path }
        return nil
    }

    private func handleClick(_ click: CommentBridge.Click) {
        guard currentFilePath != nil else { return }
        guard case .browser = click.anchor else { return }
        draft = PendingBrowserDraft(rect: click.rect, snippet: click.snippet, anchor: click.anchor)
    }

    private func commit(note: String, draft: PendingBrowserDraft) {
        guard let path = currentFilePath,
              let id = env.selectedItemID,
              let vm = env.viewModel(for: id) else {
            self.draft = nil
            return
        }
        guard case let .browser(selector, exact, prefix, suffix) = draft.anchor else {
            self.draft = nil
            return
        }
        let text = TextAnchor(exact: exact, prefix: prefix, suffix: suffix)
        let comment = Comment(
            anchor: .browser(
                filePath: path,
                textAnchor: text,
                fallbackSelector: selector,
                snippet: draft.snippet
            ),
            note: note
        )
        vm.enqueue(comment)
        self.draft = nil
    }

    private var urlBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                navButton(icon: "chevron.left", enabled: canGoBack) { webViewBox.goBack() }
                navButton(icon: "chevron.right", enabled: canGoForward) { webViewBox.goForward() }
                navButton(icon: "arrow.clockwise", enabled: true) { webViewBox.reload() }
            }

            HStack(spacing: 6) {
                Image(systemName: addressDraft.hasPrefix("file:") ? "doc" : "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.bvMuted)
                TextField("https://…", text: $addressDraft)
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.bvText)
                    .textFieldStyle(.plain)
                    .onSubmit { commit() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.bvSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.bvBorder, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func navButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(enabled ? Color.bvMuted : Color.bvBorder)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func commit() {
        var s = addressDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        if let url = URL(string: s) {
            webViewBox.load(url)
        }
    }
}

private struct PendingBrowserDraft: Identifiable, Equatable {
    let id = UUID()
    let rect: CGRect
    let snippet: String
    let anchor: CommentBridge.ClickAnchor

    static func == (lhs: PendingBrowserDraft, rhs: PendingBrowserDraft) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class WebViewBox {
    fileprivate weak var webView: WKWebView?
    fileprivate func load(_ url: URL) {
        if url.isFileURL {
            webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView?.load(URLRequest(url: url))
        }
    }
    fileprivate func goBack() { webView?.goBack() }
    fileprivate func goForward() { webView?.goForward() }
    fileprivate func reload() { webView?.reload() }
}

private struct WebViewRepresentable: NSViewRepresentable {
    let box: WebViewBox
    let commentMode: Bool
    let pins: [PinPayload]
    let onNavigate: (URL?, Bool, Bool) -> Void
    let onClick: (CommentBridge.Click) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate, onClick: onClick)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        CommentBridge.install(into: config, handler: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        box.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        context.coordinator.onClick = onClick
        context.coordinator.pendingPins = pins
        context.coordinator.pendingCommentMode = commentMode
        // Keep state in sync between navigations.
        CommentBridge.setMode(.browser, on: webView)
        CommentBridge.setCommentMode(commentMode, on: webView)
        CommentBridge.setPins(pins, on: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: CommentBridge.handlerName,
            contentWorld: CommentBridge.world
        )
        webView.configuration.userContentController.removeAllUserScripts()
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onNavigate: (URL?, Bool, Bool) -> Void
        var onClick: (CommentBridge.Click) -> Void
        var pendingPins: [PinPayload] = []
        var pendingCommentMode: Bool = false

        init(
            onNavigate: @escaping (URL?, Bool, Bool) -> Void,
            onClick: @escaping (CommentBridge.Click) -> Void
        ) {
            self.onNavigate = onNavigate
            self.onClick = onClick
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigate(webView.url, webView.canGoBack, webView.canGoForward)
            CommentBridge.setMode(.browser, on: webView)
            CommentBridge.setCommentMode(pendingCommentMode, on: webView)
            CommentBridge.setPins(pendingPins, on: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onNavigate(webView.url, webView.canGoBack, webView.canGoForward)
        }

        func userContentController(_ uc: WKUserContentController, didReceive msg: WKScriptMessage) {
            guard msg.name == CommentBridge.handlerName else { return }
            if let click = CommentBridge.decodeClick(msg.body) {
                onClick(click)
            }
        }
    }
}
