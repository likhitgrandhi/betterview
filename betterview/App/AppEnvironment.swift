import SwiftUI
import Observation

@Observable
@MainActor
final class AppEnvironment {
    let workspaceStore: WorkspaceStore
    let chatStore: ChatStore
    let runners: ClaudeRunnerRegistry
    let workflowStore: WorkflowStore
    let workflowRunners: WorkflowRunnerRegistry

    var workspaces: [Workspace] = []
    var activeWorkspaceID: UUID?
    var itemsByWorkspace: [UUID: [Item]] = [:]
    /// Workflows per workspace, loaded on boot and on workspace activation.
    var workflowsByWorkspace: [UUID: [Workflow]] = [:]
    /// Active workflow detail (when listScope is .workflows).
    var selectedWorkflowID: UUID?
    /// Live runs in memory keyed by run id; persisted to disk via WorkflowStore.
    var workflowRuns: [UUID: WorkflowRun] = [:]
    /// The run the canvas is currently bound to (if any).
    var activeRunID: UUID?
    /// Inspector panel selection on the workflow canvas.
    var selectedNodeID: UUID?
    /// Bottom run-drawer expansion state.
    var runDrawerExpanded: Bool = false
    /// Whether we're showing the "new workflow" sheet over the canvas.
    var newWorkflowSheetOpen: Bool = false
    /// Long-lived view models, keyed by item id. We cache so the event-consume
    /// Task survives across view rebuilds (otherwise transient VMs miss events).
    private var viewModels: [UUID: ItemViewModel] = [:]
    /// Selected item shown in the detail view. nil = list home.
    var selectedItemID: UUID?
    /// Used by Developer Mode multi-tab strip; ignored otherwise.
    var openItemIDs: [UUID] = []
    /// File preview opened from the file tree (developer mode only).
    var previewedFile: FileNode?
    /// Cmd+K palette toggle.
    var commandPaletteOpen: Bool = false
    /// Active "view" — either a workspace or the global "All" surface.
    var listScope: ListScope = .all
    /// User-pinned artifact for the canvas, per item. Overrides the auto-tracked
    /// "latest produced file" when set. Cleared on item delete.
    var canvasArtifact: [UUID: URL] = [:]
    /// User-pinned message for the canvas (used for text-only artifacts —
    /// long-form assistant replies that aren't backed by a file).
    /// Mutually exclusive with `canvasArtifact` for a given item.
    var canvasMessage: [UUID: UUID] = [:]

    enum ListScope: Hashable {
        case all
        case workspace(UUID)
        case workflows(UUID)
    }

    init(
        workspaceStore: WorkspaceStore = .init(),
        chatStore: ChatStore = .init(),
        runners: ClaudeRunnerRegistry = .init(),
        workflowStore: WorkflowStore = .init(),
        workflowRunners: WorkflowRunnerRegistry = .init()
    ) {
        self.workspaceStore = workspaceStore
        self.chatStore = chatStore
        self.runners = runners
        self.workflowStore = workflowStore
        self.workflowRunners = workflowRunners
    }

    var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceID else { return nil }
        return workspaces.first { $0.id == id }
    }

    /// Items currently visible per the active list scope.
    var visibleItems: [Item] {
        switch listScope {
        case .all:
            return itemsByWorkspace.values.flatMap { $0 }
        case .workspace(let id):
            return itemsByWorkspace[id] ?? []
        case .workflows(let id):
            return itemsByWorkspace[id] ?? []
        }
    }

    var totalItemCount: Int {
        itemsByWorkspace.values.reduce(0) { $0 + $1.count }
    }

    func itemCount(in workspaceID: UUID) -> Int {
        itemsByWorkspace[workspaceID]?.count ?? 0
    }

    func boot() async {
        do {
            let idx = try await workspaceStore.bootstrapped()
            self.workspaces = idx.workspaces
            self.activeWorkspaceID = idx.activeWorkspaceID
            for ws in idx.workspaces {
                await reloadItems(for: ws.id)
                await reloadWorkflows(for: ws.id)
            }
        } catch {
            NSLog("AppEnvironment.boot failed: \(error)")
        }
    }

    func reloadItems(for workspaceID: UUID) async {
        let items = await chatStore.items(in: workspaceID)
        itemsByWorkspace[workspaceID] = items
    }

    func reloadWorkflows(for workspaceID: UUID) async {
        let list = await workflowStore.workflows(in: workspaceID)
        workflowsByWorkspace[workspaceID] = list
    }

    func setActiveWorkspace(_ workspaceID: UUID) async {
        guard activeWorkspaceID != workspaceID else {
            listScope = .workspace(workspaceID)
            return
        }
        activeWorkspaceID = workspaceID
        listScope = .workspace(workspaceID)
        selectedItemID = nil
        openItemIDs = []
        previewedFile = nil
        var idx = await workspaceStore.loadIndex()
        idx.activeWorkspaceID = workspaceID
        if let i = idx.workspaces.firstIndex(where: { $0.id == workspaceID }) {
            idx.workspaces[i].lastOpenedAt = .now
        }
        try? await workspaceStore.save(idx)
        if let i = workspaces.firstIndex(where: { $0.id == workspaceID }) {
            workspaces[i].lastOpenedAt = .now
        }
        await reloadItems(for: workspaceID)
    }

    func setListScopeAll() {
        listScope = .all
        selectedItemID = nil
        previewedFile = nil
    }

    func setWorkflowScope(_ workspaceID: UUID) async {
        listScope = .workflows(workspaceID)
        selectedItemID = nil
        previewedFile = nil
        selectedWorkflowID = nil
        activeRunID = nil
        if activeWorkspaceID != workspaceID {
            await setActiveWorkspace(workspaceID)
        }
        await reloadWorkflows(for: workspaceID)
    }

    // MARK: - Workflows

    var workflowsForActiveScope: [Workflow] {
        guard case .workflows(let id) = listScope else { return [] }
        return workflowsByWorkspace[id] ?? []
    }

    func workflow(_ id: UUID) -> Workflow? {
        for (_, list) in workflowsByWorkspace {
            if let wf = list.first(where: { $0.id == id }) { return wf }
        }
        return nil
    }

    @discardableResult
    func saveWorkflow(_ workflow: Workflow) async -> Workflow {
        var wf = workflow
        wf.updatedAt = .now
        try? await workflowStore.save(wf)
        var list = workflowsByWorkspace[wf.workspaceID] ?? []
        if let idx = list.firstIndex(where: { $0.id == wf.id }) {
            list[idx] = wf
        } else {
            list.insert(wf, at: 0)
        }
        workflowsByWorkspace[wf.workspaceID] = list
        return wf
    }

    func deleteWorkflow(_ id: UUID) async {
        guard let wf = workflow(id) else { return }
        if selectedWorkflowID == id { selectedWorkflowID = nil }
        var list = workflowsByWorkspace[wf.workspaceID] ?? []
        list.removeAll { $0.id == id }
        workflowsByWorkspace[wf.workspaceID] = list
        await workflowStore.delete(workspaceID: wf.workspaceID, workflowID: id)
    }

    func openWorkflow(_ id: UUID) {
        selectedWorkflowID = id
        activeRunID = nil
        selectedNodeID = nil
        runDrawerExpanded = false
    }

    func closeWorkflow() {
        selectedWorkflowID = nil
        activeRunID = nil
        selectedNodeID = nil
        runDrawerExpanded = false
    }

    var activeWorkflow: Workflow? {
        guard let id = selectedWorkflowID else { return nil }
        return workflow(id)
    }

    var activeRun: WorkflowRun? {
        guard let id = activeRunID else { return nil }
        return workflowRuns[id]
    }

    /// Coalesce run-record disk writes so we don't full-encode JSON on every
    /// streamed text token. Milestone events (start/done/error/finished) flush
    /// immediately; text-only updates are debounced.
    private var pendingRunPersist: [UUID: Task<Void, Never>] = [:]

    func updateWorkflowRun(_ run: WorkflowRun, persistImmediately: Bool = true) {
        workflowRuns[run.id] = run
        if persistImmediately {
            pendingRunPersist[run.id]?.cancel()
            pendingRunPersist[run.id] = nil
            Task { try? await self.workflowStore.saveRun(run) }
        } else {
            // Debounce 250ms.
            pendingRunPersist[run.id]?.cancel()
            let runID = run.id
            pendingRunPersist[run.id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                if let latest = self.workflowRuns[runID] {
                    try? await self.workflowStore.saveRun(latest)
                }
                self.pendingRunPersist[runID] = nil
            }
        }
    }

    @discardableResult
    func startRun(workflow: Workflow, inputs: [String: String]) async -> WorkflowRun {
        var initial: [String: NodeRunState] = [:]
        for n in workflow.graph.nodes {
            initial[n.id.uuidString] = NodeRunState(status: n.kind == .input ? .done : .idle)
        }
        let run = WorkflowRun(
            workspaceID: workflow.workspaceID,
            workflowID: workflow.id,
            inputs: inputs,
            nodeStates: initial
        )
        workflowRuns[run.id] = run
        try? await workflowStore.saveRun(run)
        activeRunID = run.id
        runDrawerExpanded = true

        // Stamp lastRunAt on the workflow exactly ONCE per run, not on every
        // per-event tick.
        if var wf = self.workflow(workflow.id) {
            wf.lastRunAt = run.startedAt
            await saveWorkflow(wf)
        }

        guard let workspace = workspaces.first(where: { $0.id == workflow.workspaceID }) else { return run }
        let folder = workspace.folderURL
        // Pre-create the materialized run dir so the orchestrator's `mkdir -p` is cheap.
        _ = AppPaths.materializedRunDir(workspaceFolder: folder, workflowID: workflow.id, runID: run.id)

        let runner = await workflowRunners.runner(for: run.id)
        do {
            try await runner.start(workflow: workflow, run: run, workspaceFolder: folder)
            consume(runner: runner, runID: run.id, workspaceFolder: folder)
        } catch {
            var failed = run
            failed.status = .failed
            failed.finishedAt = .now
            updateWorkflowRun(failed)
            await workflowRunners.remove(runID: run.id)
        }
        return run
    }

    func cancelRun(_ runID: UUID) async {
        await workflowRunners.remove(runID: runID)
        guard var run = workflowRuns[runID] else { return }
        if run.status == .running {
            run.status = .cancelled
            run.finishedAt = .now
            updateWorkflowRun(run)
        }
    }

    private func consume(runner: WorkflowRunner, runID: UUID, workspaceFolder: URL) {
        Task { [weak self] in
            guard let self else { return }
            for await event in await runner.events {
                await self.applyRunnerEvent(event, runID: runID, workspaceFolder: workspaceFolder)
            }
        }
    }

    /// Soft caps to keep memory in check for long-running workflows.
    private static let maxTranscriptBytes = 256 * 1024
    private static let maxNodeOutputBytes = 64 * 1024

    private func applyRunnerEvent(_ event: WorkflowRunner.Event, runID: UUID, workspaceFolder: URL) {
        guard var run = workflowRuns[runID] else { return }
        var milestone = false
        switch event {
        case .sessionID(let sid):
            run.orchestratorSessionID = sid
            milestone = true
        case .orchestratorText(let text):
            run.orchestratorTranscript += text
            // Cap transcript length so memory + JSON disk size don't grow
            // without bound on a long run.
            if run.orchestratorTranscript.utf8.count > Self.maxTranscriptBytes {
                let suffix = run.orchestratorTranscript.suffix(Self.maxTranscriptBytes / 2)
                run.orchestratorTranscript = "…(transcript truncated)…\n" + String(suffix)
            }
        case .nodeStart(let nodeID):
            var st = run.nodeState(nodeID)
            st.status = .running
            st.startedAt = .now
            run.nodeStates[nodeID.uuidString] = st
            milestone = true
        case .nodeDone(let nodeID, let fileRelative):
            var st = run.nodeState(nodeID)
            st.status = .done
            st.finishedAt = .now
            if let rel = fileRelative {
                let url = workspaceFolder.appendingPathComponent(rel)
                st.outputFileURL = url
                // Cap on-disk read so a 10MB output can't balloon the run JSON.
                if let data = try? Data(contentsOf: url) {
                    let capped = data.count > Self.maxNodeOutputBytes
                        ? data.prefix(Self.maxNodeOutputBytes)
                        : data
                    if let text = String(data: capped, encoding: .utf8) {
                        st.outputText = data.count > Self.maxNodeOutputBytes
                            ? text + "\n\n…(truncated, see file for full output)…"
                            : text
                    }
                }
            }
            run.nodeStates[nodeID.uuidString] = st
            milestone = true
        case .nodeError(let nodeID, let msg):
            var st = run.nodeState(nodeID)
            st.status = .error
            st.errorMessage = msg
            st.finishedAt = .now
            run.nodeStates[nodeID.uuidString] = st
            run.status = .failed
            run.finishedAt = .now
            milestone = true
        case .finished(let ok, let err):
            if run.status == .running {
                run.status = ok ? .succeeded : .failed
            }
            if !ok, let err, run.orchestratorTranscript.isEmpty {
                run.orchestratorTranscript = err
            }
            run.finishedAt = .now
            for (k, var s) in run.nodeStates where s.status == .running {
                s.status = ok ? .done : .error
                s.finishedAt = .now
                if !ok && s.errorMessage == nil { s.errorMessage = err ?? "Run ended unexpectedly" }
                run.nodeStates[k] = s
            }
            milestone = true
            // Release the runner so it doesn't sit in the registry forever.
            let id = runID
            Task { await self.workflowRunners.remove(runID: id) }
        }
        updateWorkflowRun(run, persistImmediately: milestone)
    }

    @discardableResult
    func addWorkspace(folderURL: URL) async -> Workspace {
        let workspace = Workspace(name: folderURL.lastPathComponent, folderURL: folderURL)
        var idx = await workspaceStore.loadIndex()
        idx.workspaces.append(workspace)
        idx.activeWorkspaceID = workspace.id
        try? await workspaceStore.save(idx)
        workspaces.append(workspace)
        await setActiveWorkspace(workspace.id)
        return workspace
    }

    @discardableResult
    func newItem(in workspaceID: UUID, type: ItemType = .mixed) async -> Item {
        let item = Item(workspaceID: workspaceID, type: type)
        try? await chatStore.save(item)
        var list = itemsByWorkspace[workspaceID] ?? []
        list.insert(item, at: 0)
        itemsByWorkspace[workspaceID] = list
        if !openItemIDs.contains(item.id) { openItemIDs.append(item.id) }
        selectedItemID = item.id
        return item
    }

    func openItem(_ itemID: UUID) {
        if !openItemIDs.contains(itemID) { openItemIDs.append(itemID) }
        selectedItemID = itemID
    }

    func backToList() {
        selectedItemID = nil
    }

    func closeTab(_ itemID: UUID) async {
        openItemIDs.removeAll { $0 == itemID }
        if selectedItemID == itemID {
            selectedItemID = openItemIDs.last
        }
        await runners.remove(chatID: itemID)
    }

    func item(by id: UUID) -> Item? {
        for (_, list) in itemsByWorkspace {
            if let c = list.first(where: { $0.id == id }) { return c }
        }
        return nil
    }

    /// Returns a long-lived ItemViewModel for the given item id. Creates one
    /// on first request; subsequent calls return the same instance so the
    /// event-consume Task stays alive across view rebuilds.
    func viewModel(for itemID: UUID) -> ItemViewModel? {
        if let existing = viewModels[itemID] { return existing }
        guard let item = self.item(by: itemID) else { return nil }
        let vm = ItemViewModel(item: item, env: self)
        viewModels[itemID] = vm
        return vm
    }

    private func discardViewModel(for itemID: UUID) async {
        if let vm = viewModels[itemID] {
            await vm.stop()
        }
        viewModels[itemID] = nil
    }

    func update(_ item: Item) async {
        var list = itemsByWorkspace[item.workspaceID] ?? []
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list[idx] = item
        } else {
            list.insert(item, at: 0)
        }
        itemsByWorkspace[item.workspaceID] = list
        try? await chatStore.save(item)
    }

    /// Pin a file to the canvas for `itemID`. Clears any message pin so the
    /// two never compete.
    func pinCanvasFile(_ url: URL, for itemID: UUID) {
        canvasArtifact[itemID] = url
        canvasMessage[itemID] = nil
    }

    /// Pin (or unpin) a long-form assistant reply to the canvas. Clears any
    /// file pin. Pass `nil` to revert to auto-resolution.
    func pinCanvasMessage(_ messageID: UUID?, for itemID: UUID) {
        canvasMessage[itemID] = messageID
        if messageID != nil { canvasArtifact[itemID] = nil }
    }

    func deleteItem(_ itemID: UUID) async {
        await discardViewModel(for: itemID)
        await runners.remove(chatID: itemID)
        canvasArtifact[itemID] = nil
        canvasMessage[itemID] = nil
        openItemIDs.removeAll { $0 == itemID }
        if selectedItemID == itemID { selectedItemID = openItemIDs.last }
        guard let workspaceID = item(by: itemID)?.workspaceID
            ?? itemsByWorkspace.first(where: { $0.value.contains(where: { $0.id == itemID }) })?.key
        else { return }
        var list = itemsByWorkspace[workspaceID] ?? []
        list.removeAll { $0.id == itemID }
        itemsByWorkspace[workspaceID] = list
        await chatStore.delete(workspaceID: workspaceID, itemID: itemID)
    }
}
