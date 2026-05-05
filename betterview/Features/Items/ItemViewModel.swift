import SwiftUI
import Observation

@Observable
@MainActor
final class ItemViewModel {
    let itemID: UUID
    private let env: AppEnvironment
    private(set) var item: Item
    private(set) var isAwaitingResponse = false
    private(set) var isStartingRunner = false
    private(set) var lastError: String?
    /// Live subtitle for `working` rows in the queue panel. Transient — never persisted.
    private(set) var workingSubtitle: String = ""
    private var streamingMessageID: UUID?
    private var consumeTask: Task<Void, Never>?
    private var hasStartedRunner = false
    /// Reentrancy guard for `flushIfIdle`. MainActor isolation keeps this safe.
    private var dispatchInProgress = false
    /// Single-flight startup. Both prewarm + first send share this task so the
    /// AsyncStream consumer is created exactly once.
    private var startupTask: Task<Void, Error>?

    init(item: Item, env: AppEnvironment) {
        self.itemID = item.id
        self.item = Self.sanitizeOnLoad(item)
        self.env = env
        // If sanitization touched anything, persist the clean state so the
        // next relaunch starts clean even if the user never sends another turn.
        if self.item != item {
            let snapshot = self.item
            Task { await env.update(snapshot) }
        }
        // Prewarm in the background. Errors here are swallowed; if the user
        // hits send before this finishes, send() will await the same task.
        Task { [weak self] in
            try? await self?.ensureRunnerStarted()
        }
    }

    /// On every chat open, no Claude subprocess is actually running yet, so
    /// any persisted `isStreaming: true` message or `working` queue row is a
    /// ghost from a prior crashed/force-quit session. Demote them so the UI
    /// doesn't show a phantom thinking indicator forever.
    private static func sanitizeOnLoad(_ item: Item) -> Item {
        var clean = item
        var dirty = false
        for i in clean.messages.indices where clean.messages[i].isStreaming {
            clean.messages[i].isStreaming = false
            dirty = true
        }
        for i in clean.pendingComments.indices where clean.pendingComments[i].state == .working {
            clean.pendingComments[i].state = .queued
            clean.pendingComments[i].errorReason = "Restored from prior session"
            dirty = true
        }
        return dirty ? clean : item
    }

    var workspace: Workspace? {
        env.workspaces.first { $0.id == item.workspaceID }
    }

    var statusLine: String {
        let last = item.messages.last { $0.role == .assistant && !$0.isStreaming }
        if let last, let cost = last.costUSD, let dur = last.durationMs {
            let costStr = String(format: "$%.4f", cost)
            return "Last turn: \(costStr) · \(dur) ms"
        }
        return ""
    }

    /// Queue + auto-dispatch: every user input flows through here. Free-text
    /// from the composer becomes a `.freeform` comment; pinned comments from
    /// artifacts arrive via `enqueue(_:)` directly.
    func enqueueFreeform(_ text: String, attachmentPaths: [String] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachmentPaths.isEmpty else { return }
        enqueue(Comment(
            anchor: .freeform,
            note: trimmed.isEmpty ? "(image)" : trimmed,
            attachmentPaths: attachmentPaths
        ))
    }

    func enqueue(_ comment: Comment) {
        var c = comment
        c.state = .queued
        c.errorReason = nil
        item.pendingComments.append(c)
        item.updatedAt = .now
        Task { await env.update(item) }
        Task { await flushIfIdle() }
    }

    func removePending(id: UUID) {
        item.pendingComments.removeAll { $0.id == id && ($0.state == .queued || $0.state == .cancelled || $0.state == .orphaned) }
        Task { await env.update(item) }
    }

    func requeueCancelled(id: UUID) {
        guard let idx = item.pendingComments.firstIndex(where: { $0.id == id && $0.state == .cancelled }) else { return }
        item.pendingComments[idx].state = .queued
        item.pendingComments[idx].errorReason = nil
        Task { await env.update(item) }
        Task { await flushIfIdle() }
    }

    /// User-triggered Stop All: terminate the running batch and mark all
    /// `working` rows as `cancelled`. They do not auto-retry.
    func stopAll() async {
        for i in item.pendingComments.indices where item.pendingComments[i].state == .working {
            item.pendingComments[i].state = .cancelled
            item.pendingComments[i].errorReason = "Stopped by user"
        }
        // Tear down the in-flight assistant message so the chat doesn't stay
        // stuck on the thinking indicator.
        if let id = streamingMessageID,
           let idx = item.messages.firstIndex(where: { $0.id == id }) {
            item.messages[idx].isStreaming = false
        }
        streamingMessageID = nil
        workingSubtitle = ""
        isAwaitingResponse = false
        await env.update(item)
        await stop()
    }

    /// Drains all `queued` rows into one batched user message if the agent is idle.
    /// Reentrancy-guarded; safe to call from event handlers, enqueue, and timer.
    private func flushIfIdle() async {
        guard !dispatchInProgress, !isAwaitingResponse, !isStartingRunner else { return }
        let queuedIndices = item.pendingComments.indices.filter { item.pendingComments[$0].state == .queued }
        guard !queuedIndices.isEmpty else { return }

        dispatchInProgress = true
        defer { dispatchInProgress = false }

        // Snapshot + flip queued → working.
        for i in queuedIndices {
            item.pendingComments[i].state = .working
            item.pendingComments[i].errorReason = nil
        }
        let working = queuedIndices.map { item.pendingComments[$0] }

        let payload = serializeBatch(working)
        let userMessage = ChatMessage(role: .user, text: humanReadableTurnSummary(working), attachedComments: working)
        item.messages.append(userMessage)
        if item.title == "New Item", let first = working.first {
            item.title = String(first.note.prefix(60))
        }
        item.updatedAt = .now
        await env.update(item)

        do {
            try await ensureRunnerStarted()
            let runner = await env.runners.runner(for: itemID)
            // Aggregate image attachments from every comment in the batch.
            let imagePaths = working.flatMap { $0.attachmentPaths }
            try await runner.send(userText: payload, imagePaths: imagePaths)
            isAwaitingResponse = true
            lastError = nil
        } catch {
            // Revert: working → queued with errorReason. Drop the user message we appended.
            for i in item.pendingComments.indices where item.pendingComments[i].state == .working {
                item.pendingComments[i].state = .queued
                item.pendingComments[i].errorReason = error.localizedDescription
            }
            if item.messages.last?.id == userMessage.id { item.messages.removeLast() }
            isAwaitingResponse = false
            lastError = error.localizedDescription
            appendSystemMessage("⚠ \(error.localizedDescription)")
            await env.update(item)
        }
    }

    /// Build the CLI payload Claude actually sees. Each working comment becomes
    /// a numbered block with anchor + snippet + the user's note.
    private func serializeBatch(_ comments: [Comment]) -> String {
        guard !comments.isEmpty else { return "" }
        if comments.count == 1, case .freeform = comments[0].anchor {
            return comments[0].note
        }
        var out = "I have \(comments.count) task\(comments.count == 1 ? "" : "s") to execute. Address each in order.\n"
        for (idx, c) in comments.enumerated() {
            out += "\n[\(idx + 1)] "
            switch c.anchor {
            case .freeform:
                out += "task: \"\(c.note)\""
            case .browser(let path, _, let selector, let snippet):
                out += "browser • \(path) • selector: \(selector)\n"
                out += "    snippet: \"\(snippet.prefix(160))\"\n"
                out += "    task: \"\(c.note)\""
            case .markdown(let path, _, let blockID, let snippet):
                out += "markdown • \(path) • block: \(blockID)\n"
                out += "    snippet: \"\(snippet.prefix(160))\"\n"
                out += "    task: \"\(c.note)\""
            case .code(let path, let start, let end, let snippet, _):
                let range = start == end ? "\(start)" : "\(start)-\(end)"
                out += "code • \(path) • lines: \(range)\n"
                out += "    snippet: \"\(snippet.prefix(160))\"\n"
                out += "    task: \"\(c.note)\""
            }
        }
        return out
    }

    /// Short text shown in the user's chat bubble for an auto-dispatched batch.
    private func humanReadableTurnSummary(_ comments: [Comment]) -> String {
        if comments.count == 1, case .freeform = comments[0].anchor {
            return comments[0].note
        }
        if comments.count == 1 {
            return comments[0].note
        }
        return comments.enumerated().map { "[\($0 + 1)] \($1.note)" }.joined(separator: "\n")
    }

    func stop() async {
        consumeTask?.cancel()
        consumeTask = nil
        startupTask?.cancel()
        startupTask = nil
        await env.runners.remove(chatID: itemID)
        hasStartedRunner = false
        isAwaitingResponse = false
        isStartingRunner = false
    }

    func refreshFromStore() async {
        if let latest = env.item(by: itemID) {
            self.item = latest
        }
    }

    func setModel(_ model: String) async {
        guard item.model != model else { return }
        item.model = model
        await env.update(item)
        if hasStartedRunner {
            await env.runners.remove(chatID: itemID)
            hasStartedRunner = false
            consumeTask?.cancel()
            consumeTask = nil
            startupTask = nil
        }
    }

    func updateFacts(_ facts: [String]) async {
        item.facts = facts
        await env.update(item)
    }

    /// Record that the user has reviewed the latest assistant turn. Called
    /// when the chat detail mounts and whenever a new turn finishes while
    /// the detail is in the foreground.
    func markLatestSeen() async {
        guard let latestID = item.latestAssistantMessageID,
              item.lastSeenAssistantMessageID != latestID else { return }
        item.lastSeenAssistantMessageID = latestID
        await env.update(item)
    }

    private func ensureRunnerStarted() async throws {
        if hasStartedRunner { return }
        if let existing = startupTask {
            try await existing.value
            return
        }
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.actuallyStart()
        }
        startupTask = task
        do {
            try await task.value
        } catch {
            startupTask = nil
            isStartingRunner = false
            throw error
        }
    }

    private func actuallyStart() async throws {
        isStartingRunner = true
        defer { isStartingRunner = false }

        let runner = await env.runners.runner(for: itemID)
        let cwd = workspace?.folderURL ?? AppPaths.scratchFolder
        try await runner.start(
            cwd: cwd,
            model: item.model,
            resumeSessionID: item.claudeSessionID
        )
        hasStartedRunner = true

        let stream = await runner.events
        consumeTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event: event)
            }
            // Stream ended without a clean `.result`. Either the process died
            // or we were cancelled. Recover so the UI doesn't stay stuck on
            // the thinking indicator.
            await self?.recoverFromStreamEnd()
        }
    }

    /// Called when the runner's event stream finishes. If we were still
    /// waiting on a turn, treat it as a process death and bounce working
    /// rows back to queued so the user can retry.
    private func recoverFromStreamEnd() async {
        guard isAwaitingResponse || streamingMessageID != nil else { return }
        if let id = streamingMessageID,
           let idx = item.messages.firstIndex(where: { $0.id == id }) {
            item.messages[idx].isStreaming = false
        }
        streamingMessageID = nil
        bounceWorkingBackToQueue(reason: "Process ended unexpectedly")
        isAwaitingResponse = false
        workingSubtitle = ""
        hasStartedRunner = false
        appendSystemMessage("⚠ Claude process ended unexpectedly. Click ↻ to retry.")
        await env.update(item)
    }

    private func handle(event: ClaudeEvent) async {
        switch event {
        case .systemInit(let info):
            isStartingRunner = false
            if item.claudeSessionID == nil {
                item.claudeSessionID = info.sessionID
                if let model = info.model {
                    item.model = model
                }
                await env.update(item)
            }

        case .assistant(let msg):
            updateWorkingSubtitle(from: msg)
            if let id = streamingMessageID,
               let idx = item.messages.firstIndex(where: { $0.id == id }) {
                if !msg.text.isEmpty { item.messages[idx].text = msg.text }
                if let t = msg.thinkingText { item.messages[idx].thinkingText = t }
                item.messages[idx].toolCalls = mergedToolCalls(
                    existing: item.messages[idx].toolCalls,
                    incoming: msg.toolCalls
                )
                item.messages[idx].inputTokens = msg.inputTokens
                item.messages[idx].outputTokens = msg.outputTokens
            } else {
                // First assistant event for this turn — propagate to env so the
                // outside list reflects the running state. Per-token deltas stay
                // in the vm to avoid pounding the disk on every streamed chunk.
                let new = ChatMessage(
                    role: .assistant,
                    text: msg.text,
                    thinkingText: msg.thinkingText,
                    toolCalls: msg.toolCalls,
                    isStreaming: true,
                    inputTokens: msg.inputTokens,
                    outputTokens: msg.outputTokens
                )
                streamingMessageID = new.id
                item.messages.append(new)
                item.updatedAt = .now
                await env.update(item)
            }

        case .toolResult(let result):
            if let id = streamingMessageID,
               let idx = item.messages.firstIndex(where: { $0.id == id }),
               let toolIdx = item.messages[idx].toolCalls.firstIndex(where: { $0.id == result.toolUseID }) {
                item.messages[idx].toolCalls[toolIdx].output = result.output
                item.messages[idx].toolCalls[toolIdx].isError = result.isError
                item.messages[idx].toolCalls[toolIdx].isFinished = true
            }

        case .result(let result):
            if let id = streamingMessageID,
               let idx = item.messages.firstIndex(where: { $0.id == id }) {
                item.messages[idx].isStreaming = false
                item.messages[idx].costUSD = result.totalCostUSD
                item.messages[idx].durationMs = result.durationMs
                for i in item.messages[idx].toolCalls.indices where !item.messages[idx].toolCalls[i].isFinished {
                    item.messages[idx].toolCalls[i].isFinished = true
                }
            } else if let resultText = result.resultText, !resultText.isEmpty {
                let msg = ChatMessage(
                    role: .assistant,
                    text: resultText,
                    isStreaming: false,
                    costUSD: result.totalCostUSD,
                    durationMs: result.durationMs
                )
                item.messages.append(msg)
            }
            streamingMessageID = nil
            isAwaitingResponse = false
            workingSubtitle = ""
            // Queue state transition: working → resolved (or queued+errored).
            if result.isError {
                let reason = result.terminalReason ?? result.stopReason ?? "Claude returned an error"
                bounceWorkingBackToQueue(reason: reason)
            } else {
                drainWorkingToResolved()
            }
            item.updatedAt = .now
            await env.update(item)
            // After a successful turn, anything that arrived during it ships next.
            if !result.isError {
                await flushIfIdle()
            }

        case .diagnostic(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            appendSystemMessage(trimmed)
            isStartingRunner = false

        case .rateLimit(let info):
            // If Claude paused us, bounce the working batch back to queued so
            // the user can retry explicitly. Don't auto-flush.
            if info.status.lowercased().contains("blocked") || info.status.lowercased().contains("limit") {
                bounceWorkingBackToQueue(reason: "Rate limited (\(info.status))")
                isAwaitingResponse = false
                workingSubtitle = ""
                await env.update(item)
            }

        case .unknown:
            break
        }
    }

    private func drainWorkingToResolved() {
        // Working rows simply disappear when the batch completes. Their record
        // lives on as `attachedComments` on the user message in the transcript.
        item.pendingComments.removeAll { $0.state == .working }
    }

    private func bounceWorkingBackToQueue(reason: String) {
        for i in item.pendingComments.indices where item.pendingComments[i].state == .working {
            item.pendingComments[i].state = .queued
            item.pendingComments[i].errorReason = reason
        }
    }

    private func updateWorkingSubtitle(from msg: ClaudeEvent.AssistantMessage) {
        // Prefer the latest line of streaming text; fall back to the latest tool name.
        let line: String?
        if !msg.text.isEmpty {
            let lastLine = msg.text.split(whereSeparator: \.isNewline).last.map(String.init) ?? msg.text
            line = lastLine.trimmingCharacters(in: .whitespaces)
        } else if let tool = msg.toolCalls.last {
            line = tool.name
        } else {
            line = nil
        }
        if let line, !line.isEmpty {
            workingSubtitle = String(line.prefix(80))
        }
    }

    private func appendSystemMessage(_ text: String) {
        let msg = ChatMessage(role: .system, text: text)
        item.messages.append(msg)
        item.updatedAt = .now
        Task { await env.update(item) }
    }

    private func mergedToolCalls(existing: [ToolCall], incoming: [ToolCall]) -> [ToolCall] {
        var result = existing
        for tc in incoming {
            if let i = result.firstIndex(where: { $0.id == tc.id }) {
                result[i].name = tc.name
                result[i].inputJSON = tc.inputJSON
            } else {
                result.append(tc)
            }
        }
        return result
    }
}
