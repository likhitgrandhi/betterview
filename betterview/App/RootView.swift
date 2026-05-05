import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(BVPreferenceKey.developerMode) private var developerMode = false

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceRail()
                .frame(width: 240)
                .solidSidebar()

            Rectangle()
                .fill(Color.bvBorder)
                .frame(width: 1)
                .ignoresSafeArea()

            mainColumn
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(Color.bvBase)
        .task { await env.boot() }
        .overlay {
            if env.commandPaletteOpen {
                paletteOverlay
            }
        }
    }

    @ViewBuilder
    private var mainColumn: some View {
        ZStack {
            Color.bvBase.ignoresSafeArea()
            VStack(spacing: 0) {
                // Title-bar zone — same grey as the sidebar so the top of the
                // window reads as one continuous surface across both panes.
                Color.bvSurface.frame(height: 28)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.bvBorder).frame(height: 1)
                    }

                if developerMode && !env.openItemIDs.isEmpty {
                    ChatTabBar()
                    BVDivider()
                }

                if case .workflows = env.listScope {
                    WorkflowSurface()
                } else if let id = env.selectedItemID, env.item(by: id) != nil {
                    ItemDetailView(itemID: id)
                } else {
                    ItemListView()
                }
            }
        }
    }

    private var paletteOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { env.commandPaletteOpen = false }
            CommandPalette(isPresented: Binding(
                get: { env.commandPaletteOpen },
                set: { env.commandPaletteOpen = $0 }
            ))
            .padding(.top, 96)
        }
    }
}
