import SwiftUI

struct WorkflowDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let workflow: Workflow
    @State private var inspectorOpen: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            WorkflowToolbar(workflow: workflow, inspectorOpen: $inspectorOpen)
            BVDivider()
            HStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    WorkflowCanvasView(workflow: workflow)
                    WorkflowRunDrawer(workflow: workflow)
                }
                if inspectorOpen {
                    BVDivider(axis: .vertical)
                    WorkflowInspectorPanel(workflow: workflow)
                        .frame(width: 400)
                }
            }
        }
        .background(Color.bvBase)
    }
}
