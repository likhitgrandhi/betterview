import SwiftUI
import SwiftFlow

/// Bridges between BetterView's `Workflow` model and SwiftFlow's `FlowStore`.
/// Persistence semantics are unchanged — the workflow JSON on disk uses the
/// same `WorkflowNode` / `WorkflowEdge` shapes; this adapter just produces
/// an equivalent `FlowStore` for the canvas to render.
enum WorkflowFlowAdapter {
    static let nodeSize = CGSize(width: 140, height: 116)

    static func defaultConfiguration() -> FlowConfiguration {
        FlowConfiguration(
            defaultEdgePathType: .smoothStep,
            edgeStyle: EdgeStyle(
                strokeColor: Color.bvSubtle,
                selectedStrokeColor: Color.bvAccent,
                lineWidth: 1.5,
                selectedLineWidth: 2.0
            ),
            backgroundStyle: BackgroundStyle(
                pattern: .dot,
                color: Color.bvSubtle.opacity(0.45),
                spacing: 24,
                dotRadius: 1.4
            ),
            snapToGrid: false,
            minZoom: 0.3,
            maxZoom: 2.5
        )
    }

    /// Populate a fresh store with the workflow's nodes and edges.
    static func populate(_ store: FlowStore<WorkflowNode>, from workflow: Workflow) {
        for node in workflow.graph.nodes {
            store.addNode(makeFlowNode(from: node))
        }
        for edge in workflow.graph.edges {
            store.addEdge(makeFlowEdge(from: edge))
        }
    }

    /// Diff the workflow's structure against the store and apply add/remove
    /// operations. Positions of existing nodes are intentionally NOT touched
    /// — those are owned by the canvas while the user is interacting with it.
    static func syncStructure(_ store: FlowStore<WorkflowNode>, from workflow: Workflow) {
        let storedNodeIDs = Set(store.nodes.map(\.id))
        let desiredNodeIDs = Set(workflow.graph.nodes.map { $0.id.uuidString })
        for id in storedNodeIDs.subtracting(desiredNodeIDs) {
            store.removeNode(id)
        }
        for node in workflow.graph.nodes where !storedNodeIDs.contains(node.id.uuidString) {
            store.addNode(makeFlowNode(from: node))
        }
        let storedEdgeIDs = Set(store.edges.map(\.id))
        let desiredEdgeIDs = Set(workflow.graph.edges.map { $0.id.uuidString })
        for id in storedEdgeIDs.subtracting(desiredEdgeIDs) {
            store.removeEdge(id)
        }
        for edge in workflow.graph.edges where !storedEdgeIDs.contains(edge.id.uuidString) {
            store.addEdge(makeFlowEdge(from: edge))
        }
    }

    /// Stable hash of the workflow's structure (IDs only, no positions) so
    /// `onChange` can fire on add/remove but ignore drag updates.
    static func structuralFingerprint(_ workflow: Workflow) -> String {
        let nodes = workflow.graph.nodes.map(\.id.uuidString).sorted().joined(separator: ",")
        let edges = workflow.graph.edges.map(\.id.uuidString).sorted().joined(separator: ",")
        return nodes + "|" + edges
    }

    static func makeFlowNode(from node: WorkflowNode) -> FlowNode<WorkflowNode> {
        FlowNode(
            id: node.id.uuidString,
            position: centerToTopLeft(node.position),
            size: nodeSize,
            data: node
        )
    }

    /// Snapshot the store back into a `Workflow` value, ready for persistence.
    static func snapshot(_ store: FlowStore<WorkflowNode>, base: Workflow) -> Workflow {
        var wf = base
        for flowNode in store.nodes {
            guard let id = UUID(uuidString: flowNode.id),
                  let idx = wf.graph.nodes.firstIndex(where: { $0.id == id })
            else { continue }
            wf.graph.nodes[idx].position = topLeftToCenter(flowNode.position)
        }
        wf.graph.edges = store.edges.compactMap { e in
            guard let id = UUID(uuidString: e.id),
                  let from = UUID(uuidString: e.sourceNodeID),
                  let to = UUID(uuidString: e.targetNodeID)
            else { return nil }
            return WorkflowEdge(id: id, from: from, to: to)
        }
        return wf
    }

    static func makeFlowEdge(from edge: WorkflowEdge) -> FlowEdge {
        FlowEdge(
            id: edge.id.uuidString,
            sourceNodeID: edge.from.uuidString,
            sourceHandleID: "source",
            targetNodeID: edge.to.uuidString,
            targetHandleID: "target",
            pathType: .smoothStep
        )
    }

    /// `WorkflowNode.position` is a node *center* (pre-existing convention).
    /// SwiftFlow's `FlowNode.position` is the frame top-left. Translate at
    /// the boundary so persisted positions stay center-anchored.
    private static func centerToTopLeft(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - nodeSize.width / 2, y: p.y - nodeSize.height / 2)
    }

    private static func topLeftToCenter(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + nodeSize.width / 2, y: p.y + nodeSize.height / 2)
    }
}
