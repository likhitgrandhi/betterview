import SwiftUI
import SwiftFlow

struct WorkflowCanvasView: View {
    @Environment(AppEnvironment.self) private var env
    let workflow: Workflow

    /// Optional so we can defer creation until first appear (when callbacks
    /// can capture the live `env` and `workflow`). Once set, the same store
    /// instance is used for the lifetime of this detail view.
    @State private var store: FlowStore<WorkflowNode>?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.bvBase
            if let store {
                FlowCanvas(store: store) { flowNode, context in
                    WorkflowNodeView(
                        node: flowNode.data,
                        isSelected: flowNode.isSelected,
                        runState: env.activeRun?.nodeState(flowNode.data.id)
                    )
                    .overlay { styledHandles(for: flowNode, context: context) }
                } edgeContent: { edge, geometry in
                    edgeView(edge: edge, geometry: geometry, store: store)
                }
            }
        }
        .task { setupStoreIfNeeded() }
        .onChange(of: env.selectedNodeID) { _, new in
            syncSelectionFromEnv(new)
        }
        .onChange(of: store?.selectedNodeIDs ?? []) { _, new in
            syncSelectionToEnv(new)
        }
        .onChange(of: WorkflowFlowAdapter.structuralFingerprint(workflow)) { _, _ in
            if let store {
                WorkflowFlowAdapter.syncStructure(store, from: workflow)
            }
        }
    }

    // MARK: - Handle styling

    /// Custom handle visuals: layered on top of `FlowHandle` so SwiftFlow
    /// still anchors connections from the right point, but the user sees
    /// our accent-colored ring instead of the default gray dot.
    @ViewBuilder
    private func styledHandles(
        for flowNode: FlowNode<WorkflowNode>,
        context: NodeRenderContext
    ) -> some View {
        ForEach(flowNode.handles, id: \.id) { handle in
            FlowHandle(handle.id, type: handle.type, position: handle.position)
                .overlay {
                    Circle()
                        .fill(Color.bvBase)
                        .overlay(
                            Circle().strokeBorder(Color.bvAccent, lineWidth: 1.5)
                        )
                        .frame(width: 10, height: 10)
                        .scaleEffect(context.connectedHandleID == handle.id ? 1.25 : 1.0)
                        .animation(.bvSnappy, value: context.connectedHandleID)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: alignment(for: handle.position)
                )
        }
    }

    private func alignment(for position: HandlePosition) -> Alignment {
        switch position {
        case .top:    return .top
        case .bottom: return .bottom
        case .left:   return .leading
        case .right:  return .trailing
        }
    }

    // MARK: - Edge styling + delete

    @ViewBuilder
    private func edgeView(
        edge: FlowEdge,
        geometry: EdgeGeometry,
        store: FlowStore<WorkflowNode>
    ) -> some View {
        let stroke = StrokeStyle(
            lineWidth: edge.isSelected ? 2.0 : 1.5,
            lineCap: .round
        )
        ZStack {
            // Wide invisible hit area for easier clicking + right-click
            geometry.path
                .stroke(Color.clear, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .contentShape(geometry.path.stroke(style: StrokeStyle(lineWidth: 16)))
            // Visible stroke
            geometry.path
                .stroke(
                    edge.isSelected ? Color.bvAccent : Color.bvSubtle,
                    style: stroke
                )
        }
        .contextMenu {
            Button(role: .destructive) {
                store.removeEdge(edge.id)
                schedulePersist()
            } label: {
                Label("Delete Connection", systemImage: "trash")
            }
        }
    }

    // MARK: - Setup

    private func setupStoreIfNeeded() {
        guard store == nil else { return }
        let s = FlowStore<WorkflowNode>(
            configuration: WorkflowFlowAdapter.defaultConfiguration()
        )
        WorkflowFlowAdapter.populate(s, from: workflow)

        // New connection from drag-to-handle.
        s.onConnect = { [weak s] proposal in
            guard let s else { return }
            let edge = FlowEdge(
                id: UUID().uuidString,
                sourceNodeID: proposal.sourceNodeID,
                sourceHandleID: proposal.sourceHandleID,
                targetNodeID: proposal.targetNodeID,
                targetHandleID: proposal.targetHandleID,
                pathType: .smoothStep
            )
            s.addEdge(edge)
            schedulePersist()
        }

        // Mid-drag positions and add/remove come through here.
        s.onNodesChange = { _ in schedulePersist() }
        s.onEdgesChange = { _ in schedulePersist() }

        // Double-click an edge to delete (in addition to selection + Backspace).
        s.onEdgeDoubleTap = { [weak s] edgeID in
            guard let s else { return }
            s.removeEdge(edgeID)
            schedulePersist()
        }

        store = s
    }

    // MARK: - Persistence (debounced)

    private func schedulePersist() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            guard let store else { return }
            let updated = WorkflowFlowAdapter.snapshot(store, base: workflow)
            await env.saveWorkflow(updated)
        }
    }

    // MARK: - Selection sync

    /// One-way sync: when the inspector or another part of the app changes
    /// `env.selectedNodeID`, mirror it into the store. The reverse direction
    /// (canvas tap → inspector) is handled by observing the store's
    /// `selectedNodeIDs` from the inspector panel side, or via FlowCanvas's
    /// own selection events. For now we keep this minimal — clicking a node
    /// on the canvas selects it inside SwiftFlow; the inspector reads its
    /// selection from `env.selectedNodeID` only when the user actively
    /// chooses one elsewhere.
    private func syncSelectionFromEnv(_ id: UUID?) {
        guard let store else { return }
        if let id {
            let newID = id.uuidString
            if store.selectedNodeIDs.count == 1, store.selectedNodeIDs.contains(newID) { return }
            store.selectNode(newID, exclusive: true)
        } else if !store.selectedNodeIDs.isEmpty {
            store.clearSelection()
        }
    }

    private func syncSelectionToEnv(_ ids: Set<String>) {
        let id = ids.first.flatMap { UUID(uuidString: $0) }
        if env.selectedNodeID != id {
            env.selectedNodeID = id
        }
    }
}
