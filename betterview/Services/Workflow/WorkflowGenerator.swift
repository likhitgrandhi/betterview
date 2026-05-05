import Foundation

/// Generates a `WorkflowGraph` from a natural-language description by spawning
/// a one-shot `claude -p` and asking for JSON conforming to our schema.
struct WorkflowGenerator {
    enum GenerationError: Error, LocalizedError {
        case binaryNotFound
        case claudeFailed(String)
        case jsonNotFound
        case jsonInvalid(String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "Could not find the `claude` executable. Install Claude Code and try again."
            case .claudeFailed(let s):
                return "Claude exited with an error:\n\(s)"
            case .jsonNotFound:
                return "Claude's reply did not contain a JSON object."
            case .jsonInvalid(let s):
                return "Claude returned malformed workflow JSON: \(s)"
            }
        }
    }

    /// Returns (workflowName, summary, graph). The graph is laid out in a
    /// vertical waterfall (single column) — the canvas can refine layout later.
    static func generate(prompt: String, workspaceFolder: URL) async throws -> (String, String, WorkflowGraph) {
        guard let binary = ClaudeLocator.resolve() else { throw GenerationError.binaryNotFound }

        let system = systemPrompt
        let user = "Describe the workflow as JSON. Description from the user follows.\n\n\(prompt)"

        let p = Process()
        p.executableURL = binary
        p.arguments = [
            "-p", user,
            "--append-system-prompt", system,
            "--output-format", "text",
            "--permission-mode", "bypassPermissions",
            "--model", "sonnet",
        ]
        p.currentDirectoryURL = workspaceFolder
        var env = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = (env["PATH"].map { "\($0):\(extraPath)" }) ?? extraPath
        p.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr

        try p.run()
        // Run on a detached thread to avoid blocking the actor that called us.
        let exitStatus: Int32 = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                p.waitUntilExit()
                cont.resume(returning: p.terminationStatus)
            }
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outString = String(data: outData, encoding: .utf8) ?? ""
        let errString = String(data: errData, encoding: .utf8) ?? ""

        guard exitStatus == 0 else {
            throw GenerationError.claudeFailed(errString.isEmpty ? "exit \(exitStatus)" : errString)
        }

        guard let jsonRange = extractJSONBlock(from: outString) else {
            throw GenerationError.jsonNotFound
        }
        let jsonString = String(outString[jsonRange])
        guard let data = jsonString.data(using: .utf8) else {
            throw GenerationError.jsonInvalid("non-utf8 payload")
        }

        do {
            let raw = try JSONDecoder().decode(RawWorkflow.self, from: data)
            let graph = layout(raw.toGraph())
            return (raw.name, raw.summary, graph)
        } catch {
            throw GenerationError.jsonInvalid(error.localizedDescription)
        }
    }

    /// Falls back to a minimal "input → agent → output" template for situations
    /// where Claude is unavailable or generation fails.
    static func fallbackGraph(for prompt: String) -> (String, String, WorkflowGraph) {
        let inputNode = WorkflowNode(
            kind: .input,
            title: "Topic",
            subtitle: "Input",
            avatar: NodeAvatar.auto(seed: 1),
            inputSpec: InputSpec(label: "Topic", fieldType: .textarea, defaultValue: prompt)
        )
        let agentNode = WorkflowNode(
            kind: .agent,
            title: "Researcher",
            subtitle: "Agent",
            avatar: NodeAvatar.auto(seed: 2),
            agent: AgentSpec(
                systemPrompt: "You are a research agent. Investigate the topic thoroughly and produce a markdown summary.",
                description: "Conducts open-ended research on the input topic.",
                outputContract: "A markdown document with sections: Summary, Key Findings, Sources."
            )
        )
        let outputNode = WorkflowNode(
            kind: .output,
            title: "Report",
            subtitle: "Output",
            avatar: NodeAvatar.auto(seed: 3),
            outputSpec: OutputSpec(label: "Report", format: .markdown)
        )
        var graph = WorkflowGraph(
            nodes: [inputNode, agentNode, outputNode],
            edges: [
                WorkflowEdge(from: inputNode.id, to: agentNode.id),
                WorkflowEdge(from: agentNode.id, to: outputNode.id),
            ]
        )
        graph = layout(graph)
        return ("New Workflow", "Auto-generated fallback workflow.", graph)
    }

    // MARK: - Layout

    static func layout(_ graph: WorkflowGraph) -> WorkflowGraph {
        var graph = graph
        // Group nodes by topological "rank" (longest path from a source).
        var rank: [UUID: Int] = [:]
        let topo = graph.topologicalOrder()
        for node in topo {
            let inEdges = graph.edges.filter { $0.to == node.id }
            if inEdges.isEmpty {
                rank[node.id] = 0
            } else {
                let maxParent = inEdges.compactMap { rank[$0.from] }.max() ?? 0
                rank[node.id] = maxParent + 1
            }
        }
        // Bucket nodes per rank.
        var bucket: [Int: [UUID]] = [:]
        for n in graph.nodes {
            bucket[rank[n.id] ?? 0, default: []].append(n.id)
        }
        // Lay out: y per rank, x spread per bucket.
        let xCenter: CGFloat = 600
        let xSpacing: CGFloat = 220
        let ySpacing: CGFloat = 180
        let yStart: CGFloat = 120
        for (r, ids) in bucket {
            let count = ids.count
            for (i, id) in ids.enumerated() {
                let xOffset = CGFloat(i) - CGFloat(count - 1) / 2.0
                let pos = CGPoint(
                    x: xCenter + xOffset * xSpacing,
                    y: yStart + CGFloat(r) * ySpacing
                )
                if let idx = graph.nodes.firstIndex(where: { $0.id == id }) {
                    graph.nodes[idx].position = pos
                }
            }
        }
        return graph
    }

    // MARK: - JSON extraction

    private static func extractJSONBlock(from text: String) -> Range<String.Index>? {
        // Try fenced ```json ... ``` first.
        if let fenceStart = text.range(of: "```json") ?? text.range(of: "```JSON") {
            let afterFence = fenceStart.upperBound
            if let closing = text.range(of: "```", range: afterFence..<text.endIndex) {
                let inner = afterFence..<closing.lowerBound
                if let opening = text[inner].firstIndex(of: "{"),
                   let closingBrace = text[inner].lastIndex(of: "}") {
                    return opening..<text.index(after: closingBrace)
                }
            }
        }
        // Fallback: first { ... last }.
        if let opening = text.firstIndex(of: "{"),
           let closingBrace = text.lastIndex(of: "}"),
           opening < closingBrace {
            return opening..<text.index(after: closingBrace)
        }
        return nil
    }

    // MARK: - System prompt

    private static let systemPrompt: String = """
    You design AI workflow graphs. The user will describe a repeatable research
    or production process. You translate their description into a graph of
    inputs, agents, and outputs that can be executed by a downstream
    orchestrator.

    Reply with ONE valid JSON object and nothing else. Schema:

    {
      "name": "Short workflow name (Title Case)",
      "summary": "One-sentence description of what the workflow produces.",
      "nodes": [
        {
          "id": "node-1",
          "kind": "input" | "agent" | "output",
          "title": "Short label shown on the node",
          "subtitle": "Role line under the title (optional)",
          "input": { "label": "Field label", "fieldType": "text|textarea|file|url" },
          "agent": {
            "description": "What this agent does (one sentence)",
            "systemPrompt": "Full instructions for the agent. Be specific about tools to use, sources to consult, and output format.",
            "skills": ["web-search", "exa", "..."],
            "outputContract": "Markdown describing the expected output format/sections."
          },
          "output": { "label": "Result label", "format": "markdown|json|file" }
        }
      ],
      "edges": [ { "from": "node-1", "to": "node-2" } ]
    }

    Rules:
    - 1 input node minimum, 1 output node minimum, 2-6 agent nodes typically.
    - "id" values are arbitrary strings unique within the graph.
    - Each node must include exactly one of "input", "agent", or "output" matching its "kind".
    - Edges describe data flow from upstream → downstream.
    - System prompts MUST be concrete and actionable: name the role, the steps to take, the sources, and the desired output structure.
    - The output node's label should describe the final artifact the user receives (e.g. "Final PRD", "Competitive Brief").
    - Do not include code fences, prose, or commentary outside the JSON object.
    """

    // MARK: - Raw JSON shape (forgiving)

    private struct RawWorkflow: Decodable {
        let name: String
        let summary: String
        let nodes: [RawNode]
        let edges: [RawEdge]

        func toGraph() -> WorkflowGraph {
            var idMap: [String: UUID] = [:]
            var resolved: [WorkflowNode] = []
            for (i, n) in nodes.enumerated() {
                let uuid = UUID()
                idMap[n.id] = uuid
                let kind: NodeKind = NodeKind(rawValue: n.kind) ?? .agent
                let avatar = NodeAvatar.auto(seed: i + 1)
                var node = WorkflowNode(
                    id: uuid,
                    kind: kind,
                    title: n.title,
                    subtitle: n.subtitle,
                    avatar: avatar
                )
                if kind == .input, let raw = n.input {
                    node.inputSpec = InputSpec(
                        label: raw.label,
                        fieldType: InputSpec.FieldType(rawValue: raw.fieldType ?? "textarea") ?? .textarea,
                        defaultValue: raw.defaultValue
                    )
                }
                if kind == .agent, let raw = n.agent {
                    node.agent = AgentSpec(
                        systemPrompt: raw.systemPrompt ?? "",
                        description: raw.description ?? "",
                        attachedFiles: raw.attachedFiles ?? [],
                        skills: raw.skills ?? [],
                        model: raw.model ?? "sonnet",
                        outputContract: raw.outputContract ?? ""
                    )
                }
                if kind == .output, let raw = n.output {
                    node.outputSpec = OutputSpec(
                        label: raw.label,
                        format: OutputSpec.Format(rawValue: raw.format ?? "markdown") ?? .markdown
                    )
                }
                resolved.append(node)
            }
            var resolvedEdges: [WorkflowEdge] = []
            for e in edges {
                guard let from = idMap[e.from], let to = idMap[e.to] else { continue }
                resolvedEdges.append(WorkflowEdge(from: from, to: to))
            }
            return WorkflowGraph(nodes: resolved, edges: resolvedEdges)
        }
    }

    private struct RawNode: Decodable {
        let id: String
        let kind: String
        let title: String
        let subtitle: String?
        let input: RawInput?
        let agent: RawAgent?
        let output: RawOutput?
    }

    private struct RawInput: Decodable {
        let label: String
        let fieldType: String?
        let defaultValue: String?
    }

    private struct RawAgent: Decodable {
        let description: String?
        let systemPrompt: String?
        let attachedFiles: [String]?
        let skills: [String]?
        let model: String?
        let outputContract: String?
    }

    private struct RawOutput: Decodable {
        let label: String
        let format: String?
    }

    private struct RawEdge: Decodable {
        let from: String
        let to: String
    }
}
