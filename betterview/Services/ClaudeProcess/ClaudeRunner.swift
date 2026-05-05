import Foundation

enum ClaudeRunnerError: Error, LocalizedError {
    case binaryNotFound
    case notRunning

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Could not find the `claude` executable. Install Claude Code from https://claude.com/claude-code or set the path in Settings."
        case .notRunning:
            return "Claude subprocess is not running."
        }
    }
}

actor ClaudeRunner {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var continuation: AsyncStream<ClaudeEvent>.Continuation?
    private var stdoutBuffer = Data()

    let events: AsyncStream<ClaudeEvent>

    init() {
        var localContinuation: AsyncStream<ClaudeEvent>.Continuation!
        self.events = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
    }

    func start(cwd: URL, model: String, resumeSessionID: String?) throws {
        guard process == nil else { return }
        guard let binary = ClaudeLocator.resolve() else {
            throw ClaudeRunnerError.binaryNotFound
        }

        let p = Process()
        p.executableURL = binary
        var args: [String] = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", "bypassPermissions",
            "--model", model,
        ]
        if let prompt = Self.bundledSkillContent() {
            args.append(contentsOf: ["--append-system-prompt", prompt])
        }
        if let resume = resumeSessionID {
            args.append(contentsOf: ["--resume", resume])
        }
        p.arguments = args
        p.currentDirectoryURL = cwd

        // Log the spawn so we have a forensic trail in Console.app.
        let argString = args.map { $0.contains(" ") || $0.contains("\n") ? "<\($0.count) chars>" : $0 }.joined(separator: " ")
        NSLog("[BetterView] spawning %@ %@ (cwd=%@)", binary.path, argString, cwd.path)

        var env = ProcessInfo.processInfo.environment
        // Make sure PATH includes the common Homebrew/local paths so any helpers Claude shells out to resolve.
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = (env["PATH"].map { "\($0):\(extraPath)" }) ?? extraPath
        p.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        self.stdinHandle = stdin.fileHandleForWriting

        let cont = self.continuation

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { [weak self] in
                await self?.ingestStdout(data: data)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let s = String(data: data, encoding: .utf8) {
                NSLog("[BetterView] claude stderr: %@", s)
                cont?.yield(.diagnostic(s))
            }
        }

        p.terminationHandler = { p in
            NSLog("[BetterView] claude exited with status %d", p.terminationStatus)
            if p.terminationStatus != 0 {
                cont?.yield(.diagnostic("claude exited with status \(p.terminationStatus)"))
            }
            cont?.finish()
        }

        try p.run()
        NSLog("[BetterView] claude pid=%d started", p.processIdentifier)
        self.process = p
    }

    func send(userText: String, imagePaths: [String] = []) throws {
        guard let stdin = stdinHandle else { throw ClaudeRunnerError.notRunning }
        var content: [[String: Any]] = [["type": "text", "text": userText]]
        for path in imagePaths {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url) else { continue }
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": Self.inferMediaType(forPath: path),
                    "data": data.base64EncodedString()
                ]
            ])
        }
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": content
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var combined = data
        combined.append(0x0A) // single write so the line lands atomically
        stdin.write(combined)
        try? stdin.synchronize() // force flush so the CLI sees it immediately
        NSLog("[BetterView] sent %d bytes to claude stdin", combined.count)
    }

    private static func inferMediaType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "gif":          return "image/gif"
        case "webp":         return "image/webp"
        default:             return "image/png"
        }
    }

    func stop() {
        guard let p = process else { return }
        try? stdinHandle?.close()
        stdinHandle = nil
        if p.isRunning {
            p.terminate()
        }
        process = nil
    }

    /// Loads the bundled general-purpose behavioral skill, appended as a system prompt
    /// on every spawn so all chats are routed through it.
    private static func bundledSkillContent() -> String? {
        let url = Bundle.main.url(forResource: "general-purpose", withExtension: "md",
                                  subdirectory: "Resources/Skills")
               ?? Bundle.main.url(forResource: "general-purpose", withExtension: "md")
        guard let url, let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return content
    }

    private func ingestStdout(data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[..<nl]
            stdoutBuffer.removeSubrange(...nl)
            if let line = String(data: lineData, encoding: .utf8),
               let event = ClaudeEvent.parse(line: line) {
                continuation?.yield(event)
            }
        }
    }
}
