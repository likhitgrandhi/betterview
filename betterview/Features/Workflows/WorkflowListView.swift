import SwiftUI

struct WorkflowListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pendingDelete: Workflow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                buildPrompt
                cards
                if !workflows.isEmpty {
                    listSection
                }
                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.bvBase)
        .confirmationDialog(
            "Delete this workflow?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { wf in
            Button("Delete", role: .destructive) {
                Task { await env.deleteWorkflow(wf.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { wf in
            Text("\"\(wf.name)\" and its run history will be removed.")
        }
    }

    private var workflows: [Workflow] { env.workflowsForActiveScope }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Workflows")
                .font(BVFont.inter(22, weight: .medium))
                .tracking(0.05)
                .foregroundStyle(Color.bvText)
            Text("Repeatable agent recipes for this workspace")
                .font(BVFont.inter(11))
                .tracking(0.05)
                .foregroundStyle(Color.bvMuted)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var buildPrompt: some View {
        VStack(spacing: 12) {
            Text("What would you like to build?")
                .font(BVFont.inter(18, weight: .medium))
                .tracking(0.05)
                .foregroundStyle(Color.bvText)
            Button {
                env.newWorkflowSheetOpen = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.bvSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.bvBorder, lineWidth: 1)
                        )
                    HStack {
                        Text("Describe a research process you do over and over…")
                            .font(BVFont.inter(13))
                            .tracking(0.05)
                            .foregroundStyle(Color.bvMuted)
                        Spacer()
                        Text("⌘⇧N")
                            .font(BVFont.inter(10))
                            .foregroundStyle(Color.bvMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4).fill(Color.bvChip)
                            )
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 22)
                }
                .frame(maxWidth: 520)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
    }

    private var cards: some View {
        HStack(spacing: 14) {
            actionCard(
                icon: "plus",
                title: "Add a new agent workflow",
                subtitle: "Start from a description and let Claude scaffold the graph."
            ) {
                env.newWorkflowSheetOpen = true
            }
            actionCard(
                icon: "rectangle.stack",
                title: "Workflow Library",
                subtitle: "Coming soon — library of workspace-wide templates."
            ) { }
                .opacity(0.55)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 34)
    }

    @ViewBuilder
    private func actionCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bvText)
                    Text(title)
                        .font(BVFont.inter(13, weight: .medium))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvText)
                    Spacer()
                }
                Text(subtitle)
                    .font(BVFont.inter(11))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvMuted)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.bvSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.bvBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("YOUR WORKFLOWS · \(workflows.count)")
                    .font(BVFont.inter(10, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Color.bvMuted)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 6)

            VStack(spacing: 1) {
                ForEach(workflows) { wf in
                    workflowRow(wf)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func workflowRow(_ wf: Workflow) -> some View {
        Button {
            env.openWorkflow(wf.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: wf.graph.nodes.first?.avatar.colorHex ?? "5BA3E0").opacity(0.7))
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(wf.name)
                        .font(BVFont.inter(13, weight: .medium))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvText)
                    if !wf.summary.isEmpty {
                        Text(wf.summary)
                            .font(BVFont.inter(11))
                            .tracking(0.05)
                            .foregroundStyle(Color.bvMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("\(wf.graph.nodes.count) nodes")
                    .font(BVFont.inter(10))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvMuted)
                if let last = wf.lastRunAt {
                    Text(relativeStamp(last))
                        .font(BVFont.inter(10))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.bvSurface.opacity(0.6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { env.openWorkflow(wf.id) }
            Divider()
            Button("Delete", role: .destructive) { pendingDelete = wf }
        }
    }

    private func relativeStamp(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}
