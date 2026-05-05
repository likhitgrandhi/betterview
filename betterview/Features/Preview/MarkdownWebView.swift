import SwiftUI
@preconcurrency import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    var commentMode: Bool = false
    var pins: [PinPayload] = []
    var onClick: ((CommentBridge.Click) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onClick: onClick)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        CommentBridge.install(into: config, handler: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // Break the WKUserContentController → Coordinator strong ref so we
        // don't leak the Coordinator (and the WKWebView it holds weakly)
        // across rapid view replacements.
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: CommentBridge.handlerName,
            contentWorld: CommentBridge.world
        )
        webView.configuration.userContentController.removeAllUserScripts()
        webView.navigationDelegate = nil
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onClick = onClick
        // Reload only when the markdown body actually changed — keeps scroll +
        // pin positions stable across pin/comment-mode updates.
        if context.coordinator.lastMarkdown != markdown {
            context.coordinator.lastMarkdown = markdown
            let baseURL = Bundle.main.url(forResource: "marked.min", withExtension: "js")?
                .deletingLastPathComponent()
            let html = Self.html(for: markdown)
            webView.loadHTMLString(html, baseURL: baseURL)
            // Re-apply mode + pins after navigation finishes (Coordinator does this).
            context.coordinator.pendingPins = pins
            context.coordinator.pendingCommentMode = commentMode
        } else {
            CommentBridge.setMode(.markdown, on: webView)
            CommentBridge.setCommentMode(commentMode, on: webView)
            CommentBridge.setPins(pins, on: webView)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onClick: ((CommentBridge.Click) -> Void)?
        weak var webView: WKWebView?
        var lastMarkdown: String = ""
        var pendingPins: [PinPayload] = []
        var pendingCommentMode: Bool = false

        init(onClick: ((CommentBridge.Click) -> Void)?) {
            self.onClick = onClick
            super.init()
        }

        func userContentController(_ uc: WKUserContentController, didReceive msg: WKScriptMessage) {
            guard msg.name == CommentBridge.handlerName else { return }
            if let click = CommentBridge.decodeClick(msg.body) {
                onClick?(click)
            }
        }

        // Re-arm bridge state after each navigation (loadHTMLString triggers this).
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            CommentBridge.setMode(.markdown, on: webView)
            CommentBridge.setCommentMode(pendingCommentMode, on: webView)
            CommentBridge.setPins(pendingPins, on: webView)
        }
    }

    private static func html(for markdown: String) -> String {
        let encoded = Data(markdown.utf8).base64EncodedString()
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          :root {
            color-scheme: light;
            --bg: #FFFFFF;
            --surface: #F2F2F3;
            --border: #ECECEC;
            --text: #1A1A1A;
            --muted: #6E6E73;
            --dim: #9A9AA0;
            --accent: #D97757;
          }
          * { box-sizing: border-box; }
          html, body {
            margin: 0;
            padding: 0;
            background: var(--bg);
            color: var(--text);
            font-family: 'Inter Variable', 'Inter', -apple-system, system-ui, sans-serif;
            font-size: 13px;
            line-height: 1.7;
            letter-spacing: 0.005em;
            -webkit-font-smoothing: antialiased;
          }
          .doc { padding: 24px 28px 36px; max-width: 820px; }
          h1, h2, h3, h4, h5, h6 {
            font-weight: 500;
            margin: 1.6em 0 0.6em;
            line-height: 1.3;
            color: var(--text);
            letter-spacing: -0.005em;
          }
          h1 { font-size: 22px; padding-bottom: 8px; border-bottom: 1px solid var(--border); }
          h2 { font-size: 18px; }
          h3 { font-size: 15px; }
          h4, h5, h6 { font-size: 13px; color: var(--muted); }
          p { margin: 0.7em 0; color: var(--text); }
          a { color: var(--accent); text-decoration: none; }
          a:hover { text-decoration: underline; }
          strong { font-weight: 500; color: var(--text); }
          ul, ol { margin: 0.6em 0; padding-left: 1.5em; }
          li { margin: 0.25em 0; }
          li::marker { color: var(--dim); }
          blockquote {
            margin: 1em 0;
            padding: 0.3em 1em;
            border-left: 2px solid var(--border);
            color: var(--muted);
          }
          hr { border: 0; border-top: 1px solid var(--border); margin: 1.4em 0; }
          code {
            font-family: ui-monospace, 'SF Mono', Menlo, monospace;
            font-size: 12px;
            background: var(--surface);
            border: 1px solid var(--border);
            padding: 1px 6px;
            border-radius: 6px;
            color: var(--text);
          }
          pre {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 14px 16px;
            overflow-x: auto;
            margin: 1em 0;
          }
          pre code { background: transparent; border: none; padding: 0; border-radius: 0; font-size: 12px; line-height: 1.6; color: var(--text); }
          table { border-collapse: collapse; margin: 1em 0; font-size: 13px; width: 100%; }
          th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
          th { background: var(--surface); font-weight: 500; color: var(--text); }
          tbody tr:nth-child(even) td { background: rgba(242, 242, 243, 0.5); }
          img { max-width: 100%; height: auto; border-radius: 8px; }
          ::-webkit-scrollbar { width: 10px; height: 10px; }
          ::-webkit-scrollbar-track { background: transparent; }
          ::-webkit-scrollbar-thumb { background: #DDDDDD; border-radius: 6px; border: 2px solid #FFFFFF; }
          ::-webkit-scrollbar-thumb:hover { background: #C0C0C0; }
        </style>
        <script src="marked.min.js"></script>
        </head>
        <body>
        <div class="doc" id="content"></div>
        <script>
          (function() {
            // FNV-1a 32-bit hash → 8-char hex; cheap and good enough for block IDs.
            function fnv(s) {
              let h = 2166136261;
              for (let i = 0; i < s.length; i++) {
                h ^= s.charCodeAt(i);
                h = Math.imul(h, 16777619);
              }
              return ('00000000' + (h >>> 0).toString(16)).slice(-8);
            }
            function blockId(text) {
              const sample = (text || '').replace(/\\s+/g, ' ').trim().slice(0, 40);
              return 'bv-' + fnv(sample);
            }
            // Override block-level renderers to emit `data-bv-id` attrs the
            // CommentBridge can resolve against. Inline tokens stay untouched.
            marked.use({
              renderer: {
                paragraph(text) { return `<p data-bv-id="${blockId(text)}">${text}</p>\\n`; },
                heading(text, level) { return `<h${level} data-bv-id="${blockId(text)}">${text}</h${level}>\\n`; },
                blockquote(quote) { return `<blockquote data-bv-id="${blockId(quote)}">${quote}</blockquote>\\n`; },
                list(body, ordered) {
                  const tag = ordered ? 'ol' : 'ul';
                  return `<${tag} data-bv-id="${blockId(body)}">${body}</${tag}>\\n`;
                },
                code(code) { return `<pre data-bv-id="${blockId(code)}"><code>${code}</code></pre>\\n`; },
                table(header, body) { return `<table data-bv-id="${blockId(header + body)}"><thead>${header}</thead><tbody>${body}</tbody></table>\\n`; },
              }
            });

            const raw = atob("\(encoded)");
            const decoder = new TextDecoder("utf-8");
            const bytes = new Uint8Array([...raw].map(c => c.charCodeAt(0)));
            const text = decoder.decode(bytes);
            const opts = { gfm: true, breaks: false };
            document.getElementById("content").innerHTML = marked.parse(text, opts);
          })();
        </script>
        </body>
        </html>
        """
    }
}
