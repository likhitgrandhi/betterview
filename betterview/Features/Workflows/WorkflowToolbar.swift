import SwiftUI

struct WorkflowToolbar: View {
    @Environment(AppEnvironment.self) private var env
    let workflow: Workflow
    @Binding var inspectorOpen: Bool
    @State private var inputsSheetOpen = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                env.closeWorkflow()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bvMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to workflows")

            VStack(alignment: .leading, spacing: 1) {
                Text(workflow.name)
                    .font(BVFont.inter(13, weight: .medium))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvText)
                Text(statusLine)
                    .font(BVFont.inter(10))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvMuted)
            }

            Spacer()

            Button {
                addAgentNode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                    Text("Agent")
                        .font(BVFont.inter(11, weight: .medium))
                }
                .foregroundStyle(Color.bvText)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.bvSubtle.opacity(0.6))
                )
            }
            .buttonStyle(.plain)
            .help("Add a new agent node")

            if env.activeRun?.status == .running {
                Button {
                    Task { await cancelActiveRun() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 11))
                        Text("Stop")
                            .font(BVFont.inter(12, weight: .medium))
                    }
                    .foregroundStyle(Color.bvText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(Color.bvSubtle)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    inputsSheetOpen = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Run")
                            .font(BVFont.inter(12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(Color.bvAccent)
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                inspectorOpen.toggle()
            } label: {
                Image(systemName: inspectorOpen ? "sidebar.right" : "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundStyle(inspectorOpen ? Color.bvText : Color.bvMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Toggle inspector")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .sheet(isPresented: $inputsSheetOpen) {
            WorkflowRunInputsSheet(workflow: workflow) { inputs in
                inputsSheetOpen = false
                Task { await startRun(inputs: inputs) }
            } onCancel: {
                inputsSheetOpen = false
            }
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    private var statusLine: String {
        if let run = env.activeRun {
            switch run.status {
            case .running: return "Running…"
            case .succeeded: return "Last run succeeded"
            case .failed: return "Last run failed"
            case .cancelled: return "Last run cancelled"
            }
        }
        if !workflow.summary.isEmpty { return workflow.summary }
        return "\(workflow.graph.nodes.count) nodes"
    }

    private func startRun(inputs: [String: String]) async {
        let run = await env.startRun(workflow: workflow, inputs: inputs)
        env.activeRunID = run.id
        env.runDrawerExpanded = true
    }

    private func cancelActiveRun() async {
        guard let id = env.activeRunID else { return }
        await env.cancelRun(id)
    }

    private func addAgentNode() {
        var wf = workflow
        let seed = wf.graph.nodes.count + 1
        let baseY = wf.graph.nodes.map { $0.position.y }.max() ?? 100
        let new = WorkflowNode(
            kind: .agent,
            title: "New Agent",
            subtitle: "Agent",
            avatar: NodeAvatar.auto(seed: seed),
            position: CGPoint(x: 600, y: baseY + 180),
            agent: AgentSpec(
                systemPrompt: "Describe what this agent should do.",
                description: "New agent — edit me in the inspector.",
                outputContract: "Markdown summary."
            )
        )
        wf.graph.nodes.append(new)
        Task { await env.saveWorkflow(wf) }
        env.selectedNodeID = new.id
    }
}

struct WorkflowRunInputsSheet: View {
    let workflow: Workflow
    let onRun: ([String: String]) -> Void
    let onCancel: () -> Void
    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Run \(workflow.name)")
                    .font(BVFont.inter(15, weight: .medium))
                    .foregroundStyle(Color.bvText)
                Spacer()
                Button("Close", action: onCancel)
                    .buttonStyle(.plain)
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.bvMuted)
            }
            if workflow.inputNodes.isEmpty {
                Text("This workflow has no inputs. Click Run to start.")
                    .font(BVFont.inter(12))
                    .foregroundStyle(Color.bvMuted)
            } else {
                ForEach(workflow.inputNodes) { node in
                    inputField(for: node)
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(BVFont.inter(12))
                    .foregroundStyle(Color.bvMuted)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                Button {
                    onRun(values)
                } label: {
                    Text("Start Run")
                        .font(BVFont.inter(12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.bvAccent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(Color.bvSurface)
        .onAppear {
            for n in workflow.inputNodes {
                if let def = n.inputSpec?.defaultValue, values[n.id.uuidString] == nil {
                    values[n.id.uuidString] = def
                }
            }
        }
    }

    @ViewBuilder
    private func inputField(for node: WorkflowNode) -> some View {
        let key = node.id.uuidString
        let label = node.inputSpec?.label ?? node.title
        let binding = Binding<String>(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(BVFont.inter(11, weight: .medium))
                .foregroundStyle(Color.bvText)
            TextEditor(text: binding)
                .font(BVFont.inter(12))
                .foregroundStyle(Color.bvText)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 60, maxHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.bvBase)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.bvBorder, lineWidth: 1))
                )
        }
    }
}
