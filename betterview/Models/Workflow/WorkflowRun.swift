import Foundation

enum RunStatus: String, Codable, Hashable {
    case running
    case succeeded
    case failed
    case cancelled
}

enum NodeStatus: String, Codable, Hashable {
    case idle
    case running
    case done
    case error
}

struct NodeRunState: Codable, Hashable {
    var status: NodeStatus
    var startedAt: Date?
    var finishedAt: Date?
    var outputText: String?
    var outputFileURL: URL?
    var errorMessage: String?

    init(
        status: NodeStatus = .idle,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        outputText: String? = nil,
        outputFileURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outputText = outputText
        self.outputFileURL = outputFileURL
        self.errorMessage = errorMessage
    }
}

/// Run record for a single workflow execution. Dictionaries are keyed by
/// node-id string (UUID.uuidString) so the JSON file is human-readable.
struct WorkflowRun: Codable, Identifiable, Hashable {
    var id: UUID
    var workspaceID: UUID
    var workflowID: UUID
    var startedAt: Date
    var finishedAt: Date?
    var status: RunStatus
    var inputs: [String: String]
    var nodeStates: [String: NodeRunState]
    var orchestratorSessionID: String?
    var orchestratorTranscript: String

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        workflowID: UUID,
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        status: RunStatus = .running,
        inputs: [String: String] = [:],
        nodeStates: [String: NodeRunState] = [:],
        orchestratorSessionID: String? = nil,
        orchestratorTranscript: String = ""
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.workflowID = workflowID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.inputs = inputs
        self.nodeStates = nodeStates
        self.orchestratorSessionID = orchestratorSessionID
        self.orchestratorTranscript = orchestratorTranscript
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.workspaceID = try c.decode(UUID.self, forKey: .workspaceID)
        self.workflowID = try c.decode(UUID.self, forKey: .workflowID)
        self.startedAt = (try? c.decode(Date.self, forKey: .startedAt)) ?? .now
        self.finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        self.status = (try? c.decode(RunStatus.self, forKey: .status)) ?? .running
        self.inputs = (try? c.decode([String: String].self, forKey: .inputs)) ?? [:]
        self.nodeStates = (try? c.decode([String: NodeRunState].self, forKey: .nodeStates)) ?? [:]
        self.orchestratorSessionID = try c.decodeIfPresent(String.self, forKey: .orchestratorSessionID)
        self.orchestratorTranscript = (try? c.decode(String.self, forKey: .orchestratorTranscript)) ?? ""
    }

    nonisolated func nodeState(_ id: UUID) -> NodeRunState {
        nodeStates[id.uuidString] ?? NodeRunState()
    }
}
