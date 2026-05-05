import SwiftUI

struct NewWorkflowSheet: View {
    @Environment(AppEnvironment.self) private var env
    @State private var prompt: String = ""
    @State private var generating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New Workflow")
                    .font(BVFont.inter(15, weight: .medium))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvText)
                Spacer()
                Button {
                    env.newWorkflowSheetOpen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.bvMuted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }

            Text("Describe the process you'd like to automate. Claude will scaffold the agent graph; you can edit it after.")
                .font(BVFont.inter(11))
                .tracking(0.05)
                .foregroundStyle(Color.bvMuted)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.bvBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.bvBorder, lineWidth: 1)
                    )
                TextEditor(text: $prompt)
                    .font(BVFont.inter(12))
                    .foregroundStyle(Color.bvText)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .disabled(generating)
                if prompt.isEmpty {
                    Text("e.g. \"Competitive PRD: research direct + indirect competitors, audit our platform, list differentiators, draft a PRD in our house format.\"")
                        .font(BVFont.inter(12))
                        .foregroundStyle(Color.bvMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 160, maxHeight: 220)

            if let err = error {
                Text(err)
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .padding(.vertical, 4)
            }

            HStack {
                if generating {
                    DotMatrixLoader()
                        .frame(width: 28, height: 12)
                    Text("Designing your workflow…")
                        .font(BVFont.inter(11))
                        .foregroundStyle(Color.bvMuted)
                }
                Spacer()
                Button("Cancel") { env.newWorkflowSheetOpen = false }
                    .buttonStyle(.plain)
                    .font(BVFont.inter(12))
                    .foregroundStyle(Color.bvMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Button {
                    Task { await generate() }
                } label: {
                    Text(generating ? "Generating…" : "Generate")
                        .font(BVFont.inter(12, weight: .medium))
                        .tracking(0.05)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.bvAccent)
                                .opacity(canSubmit ? 1.0 : 0.5)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.bvSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.bvBorder, lineWidth: 1)
                )
        )
    }

    private var canSubmit: Bool {
        !generating && prompt.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    private func generate() async {
        guard canSubmit else { return }
        guard let workspaceID = workspaceIDForGeneration else { return }
        guard let workspace = env.workspaces.first(where: { $0.id == workspaceID }) else { return }

        generating = true
        error = nil
        defer { generating = false }

        let prompt = self.prompt
        do {
            let (name, summary, graph) = try await WorkflowGenerator.generate(
                prompt: prompt, workspaceFolder: workspace.folderURL
            )
            let workflow = Workflow(
                workspaceID: workspaceID,
                name: name,
                summary: summary,
                prompt: prompt,
                graph: graph
            )
            let saved = await env.saveWorkflow(workflow)
            env.newWorkflowSheetOpen = false
            env.openWorkflow(saved.id)
        } catch {
            // Offer fallback so user is never stuck.
            let (name, summary, graph) = WorkflowGenerator.fallbackGraph(for: prompt)
            let workflow = Workflow(
                workspaceID: workspaceID,
                name: name,
                summary: summary,
                prompt: prompt,
                graph: graph
            )
            let saved = await env.saveWorkflow(workflow)
            self.error = "Generation failed (\(error.localizedDescription)). Created a starter workflow you can edit."
            try? await Task.sleep(nanoseconds: 800_000_000)
            env.newWorkflowSheetOpen = false
            env.openWorkflow(saved.id)
        }
    }

    private var workspaceIDForGeneration: UUID? {
        if case .workflows(let id) = env.listScope { return id }
        return env.activeWorkspaceID
    }
}
