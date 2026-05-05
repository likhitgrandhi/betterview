import SwiftUI

struct WorkflowRunDrawer: View {
    @Environment(AppEnvironment.self) private var env
    let workflow: Workflow

    var body: some View {
        if env.activeRun != nil {
            VStack(spacing: 0) {
                handle
                if env.runDrawerExpanded {
                    BVDivider().opacity(0.6)
                    body(for: env.activeRun!)
                        .frame(maxHeight: 240)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bvSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.bvBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var handle: some View {
        Button {
            env.runDrawerExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                statusDot(for: env.activeRun!.status)
                Text(handleTitle)
                    .font(BVFont.inter(11, weight: .medium))
                    .foregroundStyle(Color.bvText)
                Spacer()
                Text(progressText)
                    .font(BVFont.inter(10))
                    .foregroundStyle(Color.bvMuted)
                Image(systemName: env.runDrawerExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.bvMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func body(for run: WorkflowRun) -> some View {
        HStack(spacing: 0) {
            // Per-node summary list.
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(workflow.graph.topologicalOrder()) { node in
                        nodeRow(node, state: run.nodeState(node.id))
                    }
                }
                .padding(10)
            }
            .frame(width: 220)
            BVDivider(axis: .vertical)
            // Orchestrator transcript.
            ScrollView {
                Text(run.orchestratorTranscript.isEmpty ? "Waiting for orchestrator output…" : run.orchestratorTranscript)
                    .font(BVFont.inter(10))
                    .foregroundStyle(Color.bvText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }
        }
    }

    private func nodeRow(_ node: WorkflowNode, state: NodeRunState) -> some View {
        Button {
            env.selectedNodeID = node.id
        } label: {
            HStack(spacing: 8) {
                Circle().fill(color(for: state.status)).frame(width: 6, height: 6)
                Text(node.title)
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.bvText)
                    .lineLimit(1)
                Spacer()
                Text(state.status.rawValue)
                    .font(BVFont.inter(9))
                    .foregroundStyle(Color.bvMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(env.selectedNodeID == node.id ? Color.bvSubtle.opacity(0.5) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusDot(for status: RunStatus) -> some View {
        Circle().fill(runColor(status)).frame(width: 8, height: 8)
    }

    private func runColor(_ status: RunStatus) -> Color {
        switch status {
        case .running: return Color.bvAccent
        case .succeeded: return Color(hex: "5DBE9C")
        case .failed: return Color.red
        case .cancelled: return Color.bvMuted
        }
    }

    private func color(for status: NodeStatus) -> Color {
        switch status {
        case .idle: return Color.bvMuted
        case .running: return Color.bvAccent
        case .done: return Color(hex: "5DBE9C")
        case .error: return Color.red
        }
    }

    private var handleTitle: String {
        guard let run = env.activeRun else { return "Run" }
        switch run.status {
        case .running: return "Run in progress"
        case .succeeded: return "Run complete"
        case .failed: return "Run failed"
        case .cancelled: return "Run cancelled"
        }
    }

    private var progressText: String {
        guard let run = env.activeRun else { return "" }
        let total = workflow.graph.nodes.filter { $0.kind == .agent }.count
        let done = run.nodeStates.values.filter { $0.status == .done }.count
        return "\(done) / \(total) agents"
    }
}
