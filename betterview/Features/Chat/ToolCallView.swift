import SwiftUI

struct ToolCallView: View {
    let tool: ToolCall
    /// If set, the parent passes the item id so we can pin this tool's
    /// produced file to the canvas on tap.
    var pinTargetItemID: UUID? = nil
    @State private var isExpanded = false
    @AppStorage(BVPreferenceKey.developerMode) private var developerMode = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)
                        .frame(width: 14)
                    Text(displayName)
                        .font(BVFont.inter(13, weight: .medium))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvText.opacity(0.85))
                    if !tool.inputSummary.isEmpty {
                        Text(tool.inputSummary)
                            .font(BVFont.inter(13))
                            .tracking(0.05)
                            .foregroundStyle(Color.bvMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    if let url = tool.producedFile, let itemID = pinTargetItemID {
                        Button {
                            env.pinCanvasFile(url, for: itemID)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10))
                                Text("Open in canvas")
                                    .font(BVFont.inter(11))
                                    .tracking(0.05)
                            }
                            .foregroundStyle(
                                env.canvasArtifact[itemID] == url
                                    ? Color.bvAccent
                                    : Color.bvMuted
                            )
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(
                                RoundedRectangle.bv(BVRadius.pill)
                                    .strokeBorder(
                                        env.canvasArtifact[itemID] == url
                                            ? Color.bvAccent.opacity(0.4)
                                            : Color.bvBorder,
                                        lineWidth: 1
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.bvMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    codeBlock(prettyInput, label: "Input")

                    if let output = tool.output, !output.isEmpty {
                        codeBlock(output, label: tool.isError ? "Error" : "Output", isError: tool.isError)
                    } else if !tool.isFinished {
                        HStack(spacing: 8) {
                            DotMatrixLoader(dotSize: 2.5, spacing: 4, cols: 4, rows: 2)
                            Text("Running…")
                                .font(BVFont.inter(13))
                                .tracking(0.05)
                                .foregroundStyle(Color.bvMuted)
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(.leading, 24)
            }
        }
    }

    private func codeBlock(_ text: String, label: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(BVFont.inter(10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Color.bvMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isError ? Color.red.opacity(0.85) : Color.bvText.opacity(0.82))
                    .textSelection(.enabled)
                    .lineLimit(20)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle.bv(BVRadius.control)
                    .fill(Color.bvSurface)
                    .overlay(
                        RoundedRectangle.bv(BVRadius.control)
                            .strokeBorder(Color.bvBorder, lineWidth: 1)
                    )
            )
        }
    }

    private var prettyInput: String {
        guard let data = tool.inputJSON.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: any, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: pretty, encoding: .utf8)
        else { return tool.inputJSON }
        return s
    }

    /// Plain-English label (default) vs raw tool name (Developer Mode).
    private var displayName: String {
        if developerMode { return tool.name }
        switch tool.name {
        case "Bash":      return "Running a command"
        case "Edit":      return "Updating file"
        case "Write":     return "Writing file"
        case "Read":      return "Reading file"
        case "Glob":      return "Finding files"
        case "Grep":      return "Searching"
        case "WebFetch":  return "Looking at a webpage"
        case "WebSearch": return "Searching the web"
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList":
            return "Updating to-dos"
        case "Task":      return "Running a sub-agent"
        case "NotebookEdit": return "Editing notebook"
        default:
            let spaced = tool.name.replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            ).lowercased()
            return "Running \(spaced)"
        }
    }

    private var statusIcon: String {
        if tool.isError { return "exclamationmark.triangle.fill" }
        if !tool.isFinished { return "circle.dotted" }
        return "checkmark"
    }

    private var statusColor: Color {
        if tool.isError { return .red.opacity(0.85) }
        if !tool.isFinished { return Color.bvAccent }
        return Color.bvAccent.opacity(0.7)
    }
}
