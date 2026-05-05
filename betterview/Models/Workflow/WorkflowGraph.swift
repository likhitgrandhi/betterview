import Foundation
import CoreGraphics

nonisolated enum NodeKind: String, Codable, Hashable, Sendable {
    case input
    case agent
    case output
}

nonisolated struct WorkflowNode: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var kind: NodeKind
    var title: String
    var subtitle: String?
    var avatar: NodeAvatar
    var position: CGPoint
    var agent: AgentSpec?
    var inputSpec: InputSpec?
    var outputSpec: OutputSpec?

    init(
        id: UUID = UUID(),
        kind: NodeKind,
        title: String,
        subtitle: String? = nil,
        avatar: NodeAvatar = NodeAvatar.auto(seed: 0),
        position: CGPoint = .zero,
        agent: AgentSpec? = nil,
        inputSpec: InputSpec? = nil,
        outputSpec: OutputSpec? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.avatar = avatar
        self.position = position
        self.agent = agent
        self.inputSpec = inputSpec
        self.outputSpec = outputSpec
    }

    /// Slug used for materialized output filenames.
    var slug: String {
        let allowed = CharacterSet.alphanumerics
        let lower = title.lowercased()
        let scalars = lower.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let s = String(scalars)
        let collapsed = s.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? id.uuidString.prefix(8).lowercased() : collapsed
    }
}

nonisolated struct WorkflowEdge: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var from: UUID
    var to: UUID

    init(id: UUID = UUID(), from: UUID, to: UUID) {
        self.id = id
        self.from = from
        self.to = to
    }
}

nonisolated struct CanvasLayout: Codable, Hashable, Sendable {
    var zoom: Double
    var offset: CGPoint

    init(zoom: Double = 1.0, offset: CGPoint = .zero) {
        self.zoom = zoom
        self.offset = offset
    }
}

nonisolated struct WorkflowGraph: Codable, Hashable, Sendable {
    var nodes: [WorkflowNode]
    var edges: [WorkflowEdge]
    var canvas: CanvasLayout

    init(nodes: [WorkflowNode] = [], edges: [WorkflowEdge] = [], canvas: CanvasLayout = .init()) {
        self.nodes = nodes
        self.edges = edges
        self.canvas = canvas
    }

    nonisolated func node(_ id: UUID) -> WorkflowNode? {
        nodes.first { $0.id == id }
    }

    nonisolated func upstream(of id: UUID) -> [WorkflowNode] {
        edges.filter { $0.to == id }.compactMap { e in node(e.from) }
    }

    nonisolated func downstream(of id: UUID) -> [WorkflowNode] {
        edges.filter { $0.from == id }.compactMap { e in node(e.to) }
    }

    /// Topological order; falls back to source order if a cycle is present.
    nonisolated func topologicalOrder() -> [WorkflowNode] {
        var inDegree: [UUID: Int] = [:]
        for n in nodes { inDegree[n.id] = 0 }
        for e in edges { inDegree[e.to, default: 0] += 1 }
        var queue = nodes.filter { (inDegree[$0.id] ?? 0) == 0 }
        var ordered: [WorkflowNode] = []
        while !queue.isEmpty {
            let n = queue.removeFirst()
            ordered.append(n)
            for e in edges where e.from == n.id {
                inDegree[e.to, default: 0] -= 1
                if inDegree[e.to] == 0, let next = node(e.to) {
                    queue.append(next)
                }
            }
        }
        return ordered.count == nodes.count ? ordered : nodes
    }
}
