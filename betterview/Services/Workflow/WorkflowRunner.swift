import Foundation

/// Runs a workflow as a single orchestrator Claude session. The orchestrator
/// is told to execute each agent (via reasoning or Task sub-agents) and to
/// emit machine-readable status markers we parse out of its assistant stream.
///
/// Status marker grammar (one per line):
///   <<NODE_START id=UUID>>
///   <<NODE_DONE id=UUID file=RELATIVE/PATH>>
///   <<NODE_ERROR id=UUID msg="...">>
///   <<RUN_DONE>>
///
/// `file=` paths are workspace-relative.
actor WorkflowRunner {
    enum Event: Sendable {
        case nodeStart(UUID)
        case nodeDone(UUID, fileRelativePath: String?)
        case nodeError(UUID, message: String)
        case orchestratorText(String)
        case sessionID(String)
        case finished(ok: Bool, error: String?)
    }

    private var process: Process?
    private var stdoutBuffer = Data()
    private var continuation: AsyncStream<Event>.Continuation?
    /// Tracks which marker we have already emitted per node so partial /
    /// repeated assistant text doesn't re-fire start/done/error events.
    private var emittedStart: Set<UUID> = []
    private var emittedDone: Set<UUID> = []
    private var emittedError: Set<UUID> = []
    private var runDoneEmitted: Bool = false
    /// Last assistant text we forwarded — used to forward only the delta,
    /// since stream-json's "assistant" event payload is cumulative within a
    /// single response chunk.
    private var lastForwardedText: String = ""
    let events: AsyncStream<Event>

    init() {
        var c: AsyncStream<Event>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in c = continuation }
        self.continuation = c
    }

    func start(workflow: Workflow, run: WorkflowRun, workspaceFolder: URL) throws {
        guard process == nil else { return }
        guard let binary = ClaudeLocator.resolve() else {
            throw ClaudeRunnerError.binaryNotFound
        }

        let p = Process()
        p.executableURL = binary
        // NOTE: we deliberately omit `--include-partial-messages` here.
        // Partial deltas would generate many duplicate assistant events, each
        // forcing marker re-parsing, transcript growth, and a full run-record
        // disk write. We only need final assistant turns for the orchestrator.
        p.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", "bypassPermissions",
            "--model", "sonnet",
        ]
        p.currentDirectoryURL = workspaceFolder

        var env = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = (env["PATH"].map { "\($0):\(extraPath)" }) ?? extraPath
        p.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        let cont = self.continuation

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { [weak self] in await self?.ingest(data: data) }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let s = String(data: data, encoding: .utf8) {
                NSLog("[BetterView/wf] stderr: %@", s)
            }
        }

        p.terminationHandler = { proc in
            NSLog("[BetterView/wf] orchestrator exited status=%d", proc.terminationStatus)
            cont?.yield(.finished(ok: proc.terminationStatus == 0, error: proc.terminationStatus == 0 ? nil : "exit \(proc.terminationStatus)"))
            cont?.finish()
        }

        try p.run()
        self.process = p
        try sendOrchestratorPrompt(workflow: workflow, run: run, stdin: stdin.fileHandleForWriting, workspaceFolder: workspaceFolder)
    }

    func stop() {
        guard let p = process else { return }
        if p.isRunning { p.terminate() }
        process = nil
        continuation?.finish()
    }

    // MARK: - Prompt

    private func sendOrchestratorPrompt(
        workflow: Workflow,
        run: WorkflowRun,
        stdin: FileHandle,
        workspaceFolder: URL
    ) throws {
        let prompt = Self.buildOrchestratorPrompt(workflow: workflow, run: run, workspaceFolder: workspaceFolder)
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var combined = data
        combined.append(0x0A)
        stdin.write(combined)
        try? stdin.synchronize()
    }

    static func buildOrchestratorPrompt(
        workflow: Workflow,
        run: WorkflowRun,
        workspaceFolder: URL
    ) -> String {
        let outputDirRelative = ".context/workflows/\(workflow.id.uuidString)/\(run.id.uuidString)"

        var nodesDesc = ""
        for node in workflow.graph.topologicalOrder() {
            nodesDesc += "\n### Node \(node.title) [id=\(node.id.uuidString)]\n"
            nodesDesc += "- Kind: \(node.kind.rawValue)\n"
            switch node.kind {
            case .input:
                let label = node.inputSpec?.label ?? node.title
                let value = run.inputs[node.id.uuidString] ?? ""
                nodesDesc += "- Label: \(label)\n"
                nodesDesc += "- User-supplied value:\n```\n\(value)\n```\n"
            case .agent:
                if let a = node.agent {
                    nodesDesc += "- Description: \(a.description)\n"
                    nodesDesc += "- Output contract: \(a.outputContract)\n"
                    nodesDesc += "- System prompt:\n```\n\(a.systemPrompt)\n```\n"
                    if !a.skills.isEmpty {
                        nodesDesc += "- Skills/tools to consider: \(a.skills.joined(separator: ", "))\n"
                    }
                }
            case .output:
                let label = node.outputSpec?.label ?? node.title
                nodesDesc += "- Label: \(label)\n"
                nodesDesc += "- Format: \(node.outputSpec?.format.rawValue ?? "markdown")\n"
            }
            let upstream = workflow.graph.upstream(of: node.id)
            if !upstream.isEmpty {
                nodesDesc += "- Receives input from: " + upstream.map { "\"\($0.title)\" [id=\($0.id.uuidString)]" }.joined(separator: ", ") + "\n"
            }
        }

        var edgesDesc = ""
        for e in workflow.graph.edges {
            if let f = workflow.graph.node(e.from), let t = workflow.graph.node(e.to) {
                edgesDesc += "- \(f.title) [\(f.id.uuidString)] → \(t.title) [\(t.id.uuidString)]\n"
            }
        }

        return """
        You are the orchestrator for a multi-agent workflow named "\(workflow.name)".

        ## Your job
        Execute every agent node in topological order. For each agent:
          1. Emit a status marker line: <<NODE_START id=THE_NODE_UUID>>
          2. Run the agent's instructions. You may either reason inline, or
             delegate the work via the Task tool to a sub-agent. Produce a
             complete, well-structured response that satisfies the agent's
             output contract.
          3. Save that response as a markdown file at:
                \(outputDirRelative)/<node-slug>.md
             where <node-slug> is a short kebab-case slug derived from the
             agent's title (e.g. "competitor-research"). Use the Write tool.
          4. Emit a marker line: <<NODE_DONE id=THE_NODE_UUID file=RELATIVE_PATH>>
             (RELATIVE_PATH is workspace-relative, e.g. \(outputDirRelative)/competitor-research.md)
          5. Pass the file path AND the inline content as context to any
             downstream agents.

        If a node fails irrecoverably, emit:
            <<NODE_ERROR id=THE_NODE_UUID msg="short reason">>
        and stop the run.

        After every node has been processed (or the run is aborted), emit
        exactly one final line:
            <<RUN_DONE>>

        ## Critical rules
        - Status markers MUST be on their OWN line and MUST appear in your
          assistant message text (NOT inside code fences). They are how the
          UI tracks progress.
        - The very first line of your response should be the first
          <<NODE_START …>> for the earliest input/agent node.
        - Always create the output directory if it doesn't exist
          (mkdir -p \(outputDirRelative)).
        - Never skip the markers; the user's UI will show "stuck" without them.
        - Use the workspace folder as your cwd. All file paths in markers must
          be workspace-relative.
        - You must not ask the user any clarifying questions — execute end to end.

        ## Workflow graph

        Edges (data flow):
        \(edgesDesc.isEmpty ? "(no edges)" : edgesDesc)

        Nodes:
        \(nodesDesc)

        ## Inputs (already supplied)
        Use the values inlined under each input node above.

        Begin now.
        """
    }

    // MARK: - Stdout ingest

    private func ingest(data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[..<nl]
            stdoutBuffer.removeSubrange(...nl)
            guard let line = String(data: lineData, encoding: .utf8),
                  let event = ClaudeEvent.parse(line: line)
            else { continue }
            handle(event: event)
        }
    }

    private func handle(event: ClaudeEvent) {
        switch event {
        case .systemInit(let init_):
            continuation?.yield(.sessionID(init_.sessionID))
        case .assistant(let msg):
            guard !msg.text.isEmpty else { return }
            // Forward the delta only. With partial messages off this is
            // typically the full chunk, but defend against repeats anyway.
            let delta: String
            if msg.text.hasPrefix(lastForwardedText) && msg.text.count > lastForwardedText.count {
                delta = String(msg.text.dropFirst(lastForwardedText.count))
            } else if msg.text == lastForwardedText {
                return
            } else {
                delta = msg.text
            }
            lastForwardedText = msg.text
            continuation?.yield(.orchestratorText(delta))
            parseMarkers(in: msg.text)
        case .result(let r):
            guard !runDoneEmitted else { return }
            runDoneEmitted = true
            continuation?.yield(.finished(ok: !r.isError, error: r.isError ? (r.resultText ?? "Run failed") : nil))
        case .toolResult, .rateLimit, .diagnostic, .unknown:
            break
        }
    }

    private func parseMarkers(in text: String) {
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("<<") else { continue }
            if let id = parseField(line: line, prefix: "<<NODE_START", field: "id") {
                if let uuid = UUID(uuidString: id), !emittedStart.contains(uuid) {
                    emittedStart.insert(uuid)
                    continuation?.yield(.nodeStart(uuid))
                }
                continue
            }
            if line.hasPrefix("<<NODE_DONE") {
                guard let id = parseField(line: line, prefix: "<<NODE_DONE", field: "id"),
                      let uuid = UUID(uuidString: id),
                      !emittedDone.contains(uuid) else { continue }
                emittedDone.insert(uuid)
                let file = parseField(line: line, prefix: "<<NODE_DONE", field: "file")
                continuation?.yield(.nodeDone(uuid, fileRelativePath: file))
                continue
            }
            if line.hasPrefix("<<NODE_ERROR") {
                guard let id = parseField(line: line, prefix: "<<NODE_ERROR", field: "id"),
                      let uuid = UUID(uuidString: id),
                      !emittedError.contains(uuid) else { continue }
                emittedError.insert(uuid)
                let msg = parseField(line: line, prefix: "<<NODE_ERROR", field: "msg") ?? "Unknown error"
                continuation?.yield(.nodeError(uuid, message: msg))
                continue
            }
            if line.hasPrefix("<<RUN_DONE>>") {
                guard !runDoneEmitted else { continue }
                runDoneEmitted = true
                continuation?.yield(.finished(ok: true, error: nil))
                continue
            }
        }
    }

    private func parseField(line: String, prefix: String, field: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        // Strip prefix and trailing >>.
        var s = line
        s.removeFirst(prefix.count)
        if s.hasSuffix(">>") { s.removeLast(2) }
        // s is like ` id=UUID file=PATH msg="..."`.
        let pattern = "\(field)="
        guard let r = s.range(of: pattern) else { return nil }
        let after = s[r.upperBound...]
        // Quoted value?
        if after.first == "\"" {
            let body = after.dropFirst()
            if let endQuote = body.firstIndex(of: "\"") {
                return String(body[..<endQuote])
            }
            return nil
        }
        // Unquoted: read until whitespace.
        let ended = after.prefix { !$0.isWhitespace }
        return ended.isEmpty ? nil : String(ended)
    }
}
