import Foundation
@preconcurrency import WebKit

/// Swift wrapper around `CommentBridge.js`. Owns the isolated content world,
/// the script-message handler, and the helpers that push state into the page.
@MainActor
enum CommentBridge {
    /// Dedicated isolated world keeps page JS from spoofing messages to the host.
    static let world: WKContentWorld = .world(name: "bv-comments")
    static let handlerName: String = "bv"

    enum Mode: String { case markdown, browser }

    /// Click event posted by `CommentBridge.js` when the user clicks an
    /// element while comment mode is on.
    struct Click {
        let anchor: ClickAnchor
        let snippet: String
        let rect: CGRect
    }

    enum ClickAnchor {
        case markdown(blockID: String?, exact: String, prefix: String, suffix: String)
        case browser(selector: String, exact: String, prefix: String, suffix: String)
    }

    /// Install the bridge into a fresh `WKWebViewConfiguration`. Returns the
    /// updated config — caller passes it to the WKWebView initializer and
    /// retains the `handler` so it stays alive.
    static func install(
        into config: WKWebViewConfiguration,
        handler: WKScriptMessageHandler
    ) {
        let controller = config.userContentController
        controller.removeAllUserScripts()
        controller.removeScriptMessageHandler(forName: handlerName, contentWorld: world)

        let source = bridgeSource()
        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: world
        )
        controller.addUserScript(script)
        controller.add(handler, contentWorld: world, name: handlerName)
    }

    static func setMode(_ mode: Mode, on webView: WKWebView) {
        webView.evaluateJavaScript("window.BV && BV.setMode('\(mode.rawValue)')", in: nil, in: world) { _ in }
    }

    static func setCommentMode(_ on: Bool, on webView: WKWebView) {
        webView.evaluateJavaScript("window.BV && BV.setCommentMode(\(on ? "true" : "false"))", in: nil, in: world) { _ in }
    }

    static func setPins(_ pins: [PinPayload], on webView: WKWebView) {
        let json = (try? JSONEncoder().encode(pins)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        webView.evaluateJavaScript("window.BV && BV.setPins(\(json))", in: nil, in: world) { _ in }
    }

    /// Decode the click payload posted by `CommentBridge.js`.
    static func decodeClick(_ body: Any) -> Click? {
        guard let dict = body as? [String: Any],
              (dict["kind"] as? String) == "click",
              let anchorDict = dict["anchor"] as? [String: Any],
              let snippet = dict["snippet"] as? String,
              let rectDict = dict["rect"] as? [String: Any]
        else { return nil }

        let x = (rectDict["x"] as? CGFloat) ?? 0
        let y = (rectDict["y"] as? CGFloat) ?? 0
        let w = (rectDict["w"] as? CGFloat) ?? 0
        let h = (rectDict["h"] as? CGFloat) ?? 0
        let rect = CGRect(x: x, y: y, width: w, height: h)

        let kind = (anchorDict["kind"] as? String) ?? "browser"
        let exact = (anchorDict["exact"] as? String) ?? ""
        let prefix = (anchorDict["prefix"] as? String) ?? ""
        let suffix = (anchorDict["suffix"] as? String) ?? ""

        let anchor: ClickAnchor
        if kind == "markdown" {
            let blockID = anchorDict["blockId"] as? String
            anchor = .markdown(blockID: blockID, exact: exact, prefix: prefix, suffix: suffix)
        } else {
            let selector = (anchorDict["selector"] as? String) ?? ""
            anchor = .browser(selector: selector, exact: exact, prefix: prefix, suffix: suffix)
        }
        return Click(anchor: anchor, snippet: snippet, rect: rect)
    }

    private static func bridgeSource() -> String {
        guard let url = Bundle.main.url(forResource: "CommentBridge", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("CommentBridge.js missing from bundle")
            return ""
        }
        return s
    }
}

/// Pin payload serialized into the JS overlay. Mirrors the shape the bridge
/// expects in `BV.setPins([...])`.
struct PinPayload: Encodable {
    let id: String
    let number: Int
    let state: String
    let anchor: AnchorPayload

    struct AnchorPayload: Encodable {
        let blockId: String?
        let selector: String?
        let exact: String
        let prefix: String
        let suffix: String
    }
}

extension PinPayload {
    /// Build pin payloads for a given file path from the chat's queue.
    /// Numbering is 1-based across the matching subset.
    static func payloads(for comments: [Comment], filePath: String, mode: CommentBridge.Mode) -> [PinPayload] {
        var out: [PinPayload] = []
        var n = 0
        for c in comments {
            switch c.anchor {
            case .markdown(let path, let textAnchor, let blockID, _) where mode == .markdown && path == filePath:
                n += 1
                out.append(PinPayload(
                    id: c.id.uuidString,
                    number: n,
                    state: c.state.rawValue,
                    anchor: .init(blockId: blockID, selector: nil, exact: textAnchor.exact, prefix: textAnchor.prefix, suffix: textAnchor.suffix)
                ))
            case .browser(let path, let textAnchor, let selector, _) where mode == .browser && path == filePath:
                n += 1
                out.append(PinPayload(
                    id: c.id.uuidString,
                    number: n,
                    state: c.state.rawValue,
                    anchor: .init(blockId: nil, selector: selector, exact: textAnchor.exact, prefix: textAnchor.prefix, suffix: textAnchor.suffix)
                ))
            default:
                continue
            }
        }
        return out
    }
}
