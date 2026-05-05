import SwiftUI

struct WorkflowSurface: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            Color.bvBase.ignoresSafeArea()
            if let wf = env.activeWorkflow {
                WorkflowDetailView(workflow: wf)
            } else {
                WorkflowListView()
            }
            if env.newWorkflowSheetOpen {
                sheetOverlay
            }
        }
    }

    private var sheetOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { env.newWorkflowSheetOpen = false }
            NewWorkflowSheet()
                .frame(maxWidth: 620)
                .padding(40)
        }
    }
}
