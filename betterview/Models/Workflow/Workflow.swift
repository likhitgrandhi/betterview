import Foundation

struct Workflow: Codable, Identifiable, Hashable {
    var id: UUID
    var workspaceID: UUID
    var name: String
    var summary: String
    var prompt: String
    var graph: WorkflowGraph
    var createdAt: Date
    var updatedAt: Date
    var lastRunAt: Date?

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        name: String,
        summary: String = "",
        prompt: String = "",
        graph: WorkflowGraph = .init(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.summary = summary
        self.prompt = prompt
        self.graph = graph
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunAt = lastRunAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.workspaceID = try c.decode(UUID.self, forKey: .workspaceID)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Workflow"
        self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        self.prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        self.graph = (try? c.decode(WorkflowGraph.self, forKey: .graph)) ?? .init()
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? .now
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? .now
        self.lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
    }

    nonisolated var inputNodes: [WorkflowNode] { graph.nodes.filter { $0.kind == .input } }
    nonisolated var agentNodes: [WorkflowNode] { graph.nodes.filter { $0.kind == .agent } }
    nonisolated var outputNodes: [WorkflowNode] { graph.nodes.filter { $0.kind == .output } }
}
