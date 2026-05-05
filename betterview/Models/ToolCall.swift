import Foundation

struct ToolCall: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var inputJSON: String
    var output: String?
    var isError: Bool
    var isFinished: Bool

    init(
        id: String,
        name: String,
        inputJSON: String = "{}",
        output: String? = nil,
        isError: Bool = false,
        isFinished: Bool = false
    ) {
        self.id = id
        self.name = name
        self.inputJSON = inputJSON
        self.output = output
        self.isError = isError
        self.isFinished = isFinished
    }

    /// If this tool call created or modified a file, returns its URL.
    /// Used to make the tool card a handle that opens the artifact in the canvas.
    var producedFile: URL? {
        let fileTools: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit"]
        guard fileTools.contains(name),
              let data = inputJSON.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any],
              let path = (dict["file_path"] as? String) ?? (dict["notebook_path"] as? String),
              !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Best-effort short summary of the input for the row label.
    var inputSummary: String {
        guard let data = inputJSON.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any],
              !dict.isEmpty
        else { return "" }
        let interesting = ["file_path", "path", "command", "url", "pattern", "query", "description"]
        for key in interesting {
            if let v = dict[key] as? String, !v.isEmpty {
                return v
            }
        }
        if let first = dict.first, let v = first.value as? String, !v.isEmpty {
            return "\(first.key): \(v)"
        }
        return inputJSON.prefix(80).description
    }
}
