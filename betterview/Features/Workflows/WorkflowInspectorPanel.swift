import SwiftUI
import AppKit

struct WorkflowInspectorPanel: View {
    @Environment(AppEnvironment.self) private var env
    let workflow: Workflow
    @State private var selectedTab: Tab = .general

    enum Tab: String, CaseIterable, Hashable {
        case general = "General"
        case instructions = "Instructions"
        case budget = "Budget"
        case files = "Files"
        case advanced = "Advanced"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            BVDivider()
            tabBar
            BVDivider().opacity(0.6)
            ScrollView {
                content
                    .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color.bvSurface)
    }

    private var node: WorkflowNode? {
        guard let id = env.selectedNodeID else { return nil }
        return workflow.graph.node(id)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let n = node {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: n.avatar.colorHex),
                                    Color(hex: n.avatar.colorHex).opacity(0.6),
                                ],
                                center: .topLeading, startRadius: 2, endRadius: 30
                            )
                        )
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.title)
                        .font(BVFont.inter(13, weight: .medium))
                        .foregroundStyle(Color.bvText)
                    Text(roleLine(for: n))
                        .font(BVFont.inter(10))
                        .foregroundStyle(Color.bvMuted)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(workflow.name)
                        .font(BVFont.inter(13, weight: .medium))
                        .foregroundStyle(Color.bvText)
                    Text(workflow.summary.isEmpty ? "Workflow" : workflow.summary)
                        .font(BVFont.inter(10))
                        .foregroundStyle(Color.bvMuted)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(BVFont.inter(11, weight: selectedTab == tab ? .medium : .regular))
                        .foregroundStyle(selectedTab == tab ? Color.bvText : Color.bvMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selectedTab == tab ? Color.bvSubtle.opacity(0.6) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let n = node {
            switch selectedTab {
            case .general: generalTab(node: n)
            case .instructions: instructionsTab(node: n)
            case .files: filesTab(node: n)
            case .budget: comingSoonTab("Budget", subtitle: "Per-agent token + cost limits coming soon.")
            case .advanced: advancedTab(node: n)
            }
        } else {
            workflowOverview
        }
    }

    private var workflowOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("ABOUT")
            Text(workflow.summary.isEmpty ? "No description provided." : workflow.summary)
                .font(BVFont.inter(12))
                .foregroundStyle(Color.bvText)
            sectionLabel("ORIGINAL PROMPT")
            Text(workflow.prompt.isEmpty ? "—" : workflow.prompt)
                .font(BVFont.inter(11))
                .foregroundStyle(Color.bvMuted)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.bvBase))
            sectionLabel("STATS")
            HStack(spacing: 18) {
                stat("Nodes", "\(workflow.graph.nodes.count)")
                stat("Edges", "\(workflow.graph.edges.count)")
                stat("Inputs", "\(workflow.inputNodes.count)")
                stat("Outputs", "\(workflow.outputNodes.count)")
            }
            Text("Click a node on the canvas to inspect or edit it.")
                .font(BVFont.inter(10))
                .foregroundStyle(Color.bvMuted)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func generalTab(node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("PROFILE")
            editableField("Name", text: titleBinding(for: node))
            if node.kind == .agent {
                editableField("Description", text: agentDescBinding(for: node), multiline: true)
                sectionLabel("OUTPUT CONTRACT")
                editableField("", text: outputContractBinding(for: node), multiline: true)
            }
            if node.kind == .input, let spec = node.inputSpec {
                editableField("Label", text: inputLabelBinding(for: node))
                Text("Field type: \(spec.fieldType.rawValue)")
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.bvMuted)
            }
            if node.kind == .output, let spec = node.outputSpec {
                editableField("Label", text: outputLabelBinding(for: node))
                Text("Format: \(spec.format.rawValue)")
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.bvMuted)
            }

            if let runState = env.activeRun?.nodeState(node.id), runState.status != .idle {
                BVDivider().padding(.vertical, 4)
                sectionLabel("LATEST RUN")
                runStateBlock(runState)
            }
        }
    }

    @ViewBuilder
    private func instructionsTab(node: WorkflowNode) -> some View {
        if node.kind == .agent {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("MAIN PROMPT")
                editableField("", text: systemPromptBinding(for: node), multiline: true, minHeight: 240)
                Text("Edits save automatically and apply on the next run.")
                    .font(BVFont.inter(10))
                    .foregroundStyle(Color.bvMuted)
            }
        } else {
            Text("Instructions are only available on agent nodes.")
                .font(BVFont.inter(11))
                .foregroundStyle(Color.bvMuted)
        }
    }

    @ViewBuilder
    private func filesTab(node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("ATTACHED FILES")
            if node.kind == .agent {
                if let files = node.agent?.attachedFiles, !files.isEmpty {
                    ForEach(files, id: \.self) { f in
                        HStack {
                            Image(systemName: "doc")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.bvMuted)
                            Text(f).font(BVFont.inter(11)).foregroundStyle(Color.bvText)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Text("No files attached. The agent will see whatever the workspace folder contains.")
                        .font(BVFont.inter(11))
                        .foregroundStyle(Color.bvMuted)
                }
            } else {
                Text("Only agents can have attached files.")
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.bvMuted)
            }
        }
    }

    @ViewBuilder
    private func advancedTab(node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("METADATA")
            Text("Node id: \(node.id.uuidString)")
                .font(BVFont.inter(10))
                .foregroundStyle(Color.bvMuted)
                .textSelection(.enabled)
            if node.kind == .agent {
                sectionLabel("MODEL")
                Text(node.agent?.model ?? "sonnet")
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.bvText)
            }
            BVDivider().padding(.vertical, 4)
            Button {
                deleteNode(node)
            } label: {
                Text("Delete node")
                    .font(BVFont.inter(11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.8)))
            }
            .buttonStyle(.plain)
        }
    }

    private func comingSoonTab(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BVFont.inter(13, weight: .medium))
                .foregroundStyle(Color.bvText)
            Text(subtitle)
                .font(BVFont.inter(11))
                .foregroundStyle(Color.bvMuted)
        }
    }

    // MARK: - Building blocks

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(BVFont.inter(9, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(Color.bvMuted)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(BVFont.inter(13, weight: .medium))
                .foregroundStyle(Color.bvText)
            Text(label)
                .font(BVFont.inter(9, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Color.bvMuted)
        }
    }

    @ViewBuilder
    private func editableField(_ label: String, text: Binding<String>, multiline: Bool = false, minHeight: CGFloat = 36) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(BVFont.inter(10, weight: .medium))
                    .foregroundStyle(Color.bvText)
            }
            if multiline {
                TextEditor(text: text)
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.bvText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: minHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.bvBase)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.bvBorder, lineWidth: 1))
                    )
            } else {
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .font(BVFont.inter(12))
                    .foregroundStyle(Color.bvText)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.bvBase)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.bvBorder, lineWidth: 1))
                    )
            }
        }
    }

    private func runStateBlock(_ state: NodeRunState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.status.rawValue.uppercased())
                    .font(BVFont.inter(9, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Color.bvAccent)
                Spacer()
                if let f = state.outputFileURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([f])
                    } label: {
                        Text("Reveal file")
                            .font(BVFont.inter(10))
                            .foregroundStyle(Color.bvAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let err = state.errorMessage {
                Text(err)
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.red.opacity(0.85))
            }
            if let out = state.outputText, !out.isEmpty {
                ScrollView {
                    Text(out)
                        .font(BVFont.inter(10))
                        .foregroundStyle(Color.bvText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.bvBase))
            }
        }
    }

    private func roleLine(for node: WorkflowNode) -> String {
        switch node.kind {
        case .input: return "Input"
        case .agent: return node.agent?.description ?? "Agent"
        case .output: return "Output"
        }
    }

    // MARK: - Bindings (write-through to env.saveWorkflow)

    private func titleBinding(for node: WorkflowNode) -> Binding<String> {
        nodeBinding(node) { $0.title } set: { $0.title = $1 }
    }

    private func agentDescBinding(for node: WorkflowNode) -> Binding<String> {
        nodeBinding(node) { $0.agent?.description ?? "" } set: { n, v in
            if n.agent == nil { n.agent = AgentSpec() }
            n.agent?.description = v
        }
    }

    private func systemPromptBinding(for node: WorkflowNode) -> Binding<String> {
        nodeBinding(node) { $0.agent?.systemPrompt ?? "" } set: { n, v in
            if n.agent == nil { n.agent = AgentSpec() }
            n.agent?.systemPrompt = v
        }
    }

    private func outputContractBinding(for node: WorkflowNode) -> Binding<String> {
        nodeBinding(node) { $0.agent?.outputContract ?? "" } set: { n, v in
            if n.agent == nil { n.agent = AgentSpec() }
            n.agent?.outputContract = v
        }
    }

    private func inputLabelBinding(for node: WorkflowNode) -> Binding<String> {
        nodeBinding(node) { $0.inputSpec?.label ?? "" } set: { n, v in
            if n.inputSpec == nil { n.inputSpec = InputSpec(label: v) }
            n.inputSpec?.label = v
        }
    }

    private func outputLabelBinding(for node: WorkflowNode) -> Binding<String> {
        nodeBinding(node) { $0.outputSpec?.label ?? "" } set: { n, v in
            if n.outputSpec == nil { n.outputSpec = OutputSpec(label: v) }
            n.outputSpec?.label = v
        }
    }

    private func nodeBinding(
        _ node: WorkflowNode,
        get: @escaping (WorkflowNode) -> String,
        set: @escaping (inout WorkflowNode, String) -> Void
    ) -> Binding<String> {
        Binding<String>(
            get: { get(node) },
            set: { newValue in
                var wf = workflow
                guard let idx = wf.graph.nodes.firstIndex(where: { $0.id == node.id }) else { return }
                set(&wf.graph.nodes[idx], newValue)
                Task { await env.saveWorkflow(wf) }
            }
        )
    }

    private func deleteNode(_ node: WorkflowNode) {
        var wf = workflow
        wf.graph.nodes.removeAll { $0.id == node.id }
        wf.graph.edges.removeAll { $0.from == node.id || $0.to == node.id }
        env.selectedNodeID = nil
        Task { await env.saveWorkflow(wf) }
    }
}
