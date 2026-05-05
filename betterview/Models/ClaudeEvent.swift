import Foundation

enum ClaudeEvent: Sendable {
    case systemInit(SystemInit)
    case assistant(AssistantMessage)
    case toolResult(ToolResult)
    case result(Result)
    case rateLimit(RateLimit)
    case diagnostic(String)
    case unknown(rawType: String, json: String)

    struct SystemInit: Sendable {
        var sessionID: String
        var cwd: String?
        var model: String?
        var permissionMode: String?
    }

    struct AssistantMessage: Sendable {
        var sessionID: String
        var text: String
        var thinkingText: String?
        var toolCalls: [ToolCall]
        var inputTokens: Int?
        var outputTokens: Int?
    }

    struct ToolResult: Sendable {
        var sessionID: String
        var toolUseID: String
        var output: String
        var isError: Bool
    }

    struct Result: Sendable {
        var sessionID: String
        var isError: Bool
        var resultText: String?
        var totalCostUSD: Double?
        var durationMs: Int?
        var stopReason: String?
        var terminalReason: String?
    }

    struct RateLimit: Sendable {
        var sessionID: String
        var status: String
        var resetsAt: Int?
    }
}

extension ClaudeEvent {
    static func parse(line: String) -> ClaudeEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any]
        else { return nil }

        let type = (dict["type"] as? String) ?? ""
        let sessionID = (dict["session_id"] as? String) ?? ""

        switch type {
        case "system":
            let cwd = dict["cwd"] as? String
            let model = dict["model"] as? String
            let permissionMode = dict["permissionMode"] as? String
            return .systemInit(.init(
                sessionID: sessionID,
                cwd: cwd,
                model: model,
                permissionMode: permissionMode
            ))

        case "assistant":
            let message = dict["message"] as? [String: Any]
            let content = message?["content"] as? [[String: Any]] ?? []

            let text = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "text" else { return nil }
                return item["text"] as? String
            }.joined()

            let thinkingText = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "thinking" else { return nil }
                return item["thinking"] as? String
            }.joined()

            let toolCalls: [ToolCall] = content.compactMap { item in
                guard (item["type"] as? String) == "tool_use",
                      let id = item["id"] as? String,
                      let name = item["name"] as? String
                else { return nil }
                let input = item["input"] as? [String: Any] ?? [:]
                let inputJSON: String
                if let data = try? JSONSerialization.data(
                    withJSONObject: input,
                    options: [.sortedKeys]
                ), let s = String(data: data, encoding: .utf8) {
                    inputJSON = s
                } else {
                    inputJSON = "{}"
                }
                return ToolCall(id: id, name: name, inputJSON: inputJSON)
            }

            let usage = message?["usage"] as? [String: Any]
            return .assistant(.init(
                sessionID: sessionID,
                text: text,
                thinkingText: thinkingText.isEmpty ? nil : thinkingText,
                toolCalls: toolCalls,
                inputTokens: usage?["input_tokens"] as? Int,
                outputTokens: usage?["output_tokens"] as? Int
            ))

        case "user":
            // user events arrive when a tool returns. We surface the first tool_result.
            let message = dict["message"] as? [String: Any]
            let content = message?["content"] as? [[String: Any]] ?? []
            for item in content {
                guard (item["type"] as? String) == "tool_result",
                      let toolUseID = item["tool_use_id"] as? String
                else { continue }
                let isError = (item["is_error"] as? Bool) ?? false
                let output = extractToolResultText(item["content"])
                return .toolResult(.init(
                    sessionID: sessionID,
                    toolUseID: toolUseID,
                    output: output,
                    isError: isError
                ))
            }
            return nil

        case "result":
            let isError = (dict["is_error"] as? Bool) ?? false
            let resultText = dict["result"] as? String
            let cost = dict["total_cost_usd"] as? Double
            let duration = dict["duration_ms"] as? Int
            let stopReason = dict["stop_reason"] as? String
            let terminalReason = dict["terminal_reason"] as? String
            return .result(.init(
                sessionID: sessionID,
                isError: isError,
                resultText: resultText,
                totalCostUSD: cost,
                durationMs: duration,
                stopReason: stopReason,
                terminalReason: terminalReason
            ))

        case "rate_limit_event":
            let info = dict["rate_limit_info"] as? [String: Any]
            let status = (info?["status"] as? String) ?? "unknown"
            let resetsAt = info?["resetsAt"] as? Int
            return .rateLimit(.init(
                sessionID: sessionID,
                status: status,
                resetsAt: resetsAt
            ))

        default:
            return .unknown(rawType: type, json: trimmed)
        }
    }

    private static func extractToolResultText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            let parts = arr.compactMap { item -> String? in
                if (item["type"] as? String) == "text" {
                    return item["text"] as? String
                }
                return nil
            }
            return parts.joined(separator: "\n")
        }
        return ""
    }
}
