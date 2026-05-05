import SwiftUI
import AppKit

struct WorkspaceRail: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openSettings) private var openSettings
    @AppStorage(BVPreferenceKey.developerMode) private var developerMode = false

    var body: some View {
        VStack(spacing: 0) {
            // Reserved zone for the macOS traffic-light buttons (the window
            // uses a hidden title bar, so we need to keep this region clear).
            Color.clear.frame(height: 28)
            brand
            search
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            scopeSection
            workspacesSection
            Spacer(minLength: 0)
            profileCell
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Brand

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle.bv(10)
                    .fill(Color.bvAccent)
                Text("BV")
                    .font(BVFont.inter(13, weight: .medium))
                    .tracking(0.05)
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)

            Text("BetterView")
                .font(BVFont.inter(13, weight: .medium))
                .tracking(0.05)
                .foregroundStyle(Color.bvText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Search

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.bvMuted)
            Text("Quick open…")
                .font(BVFont.inter(13))
                .tracking(0.05)
                .foregroundStyle(Color.bvMuted)
            Spacer()
            Text("⌘K")
                .font(BVFont.inter(11, weight: .medium))
                .tracking(0.05)
                .foregroundStyle(Color.bvMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle.bv(6)
                        .fill(Color.bvBase)
                        .overlay(
                            RoundedRectangle.bv(6)
                                .strokeBorder(Color.bvBorder, lineWidth: 1)
                        )
                )
        }
        .padding(.horizontal, 12)
        .frame(height: BVMetrics.sidebarRow)
        .background(
            RoundedRectangle.bv(BVRadius.control)
                .fill(Color.bvBase)
                .overlay(
                    RoundedRectangle.bv(BVRadius.control)
                        .strokeBorder(Color.bvBorder, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { env.commandPaletteOpen = true }
    }

    // MARK: - Scope / workspaces

    private var scopeSection: some View {
        VStack(spacing: 2) {
            sectionHeader("WORKSPACES")
            scopeRow(
                isActive: env.listScope == .all,
                icon: "tray",
                title: "All",
                count: env.totalItemCount
            ) {
                env.setListScopeAll()
            }
        }
        .padding(.bottom, 6)
    }

    private var workspacesSection: some View {
        VStack(spacing: 2) {
            ForEach(sortedWorkspaces) { ws in
                scopeRow(
                    isActive: isActiveWorkspace(ws),
                    icon: ws.isScratch ? "doc.text" : "folder",
                    title: ws.name,
                    count: env.itemCount(in: ws.id)
                ) {
                    Task { await env.setActiveWorkspace(ws.id) }
                }
                .contextMenu {
                    if !ws.isScratch {
                        Button("Reveal in Finder") { reveal(ws.folderURL) }
                    }
                }
                if isActiveWorkspace(ws) || isWorkflowScope(ws) {
                    workflowsSubRow(for: ws)
                }
            }
            Button {
                openFolder()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.bvMuted)
                        .frame(width: 16)
                    Text("Open Folder…")
                        .font(BVFont.inter(13))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: BVMetrics.sidebarRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func sectionHeader(_ s: String) -> some View {
        HStack {
            Text(s)
                .font(BVFont.inter(10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Color.bvMuted)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func scopeRow(
        isActive: Bool,
        icon: String,
        title: String,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        SidebarRowButton(
            isActive: isActive,
            minHeight: BVMetrics.sidebarRow,
            action: action
        ) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color.bvText : Color.bvMuted)
                    .frame(width: 16)
                Text(title)
                    .font(BVFont.inter(13, weight: isActive ? .medium : .regular))
                    .tracking(0.05)
                    .foregroundStyle(isActive ? Color.bvText : Color.bvText.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(BVFont.inter(11))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Profile

    private var profileCell: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.bvSubtle)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bvMuted)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(NSFullUserName().isEmpty ? "You" : NSFullUserName())
                    .font(BVFont.inter(13, weight: .medium))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvText)
                    .lineLimit(1)
                if developerMode {
                    Text("Developer Mode")
                        .font(BVFont.inter(10))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvAccent)
                }
            }
            Spacer()
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.bvMuted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle.bv(BVRadius.pill)
                            .fill(Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(SidebarIconButtonStyle())
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.bvBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Helpers

    private func isActiveWorkspace(_ ws: Workspace) -> Bool {
        if case .workspace(let id) = env.listScope, id == ws.id { return true }
        if case .workflows(let id) = env.listScope, id == ws.id { return true }
        return false
    }

    private func isWorkflowScope(_ ws: Workspace) -> Bool {
        if case .workflows(let id) = env.listScope, id == ws.id { return true }
        return false
    }

    @ViewBuilder
    private func workflowsSubRow(for ws: Workspace) -> some View {
        let active = isWorkflowScope(ws)
        let count = env.workflowsByWorkspace[ws.id]?.count ?? 0
        SidebarRowButton(
            isActive: active,
            minHeight: 32
        ) {
            Task { await env.setWorkflowScope(ws.id) }
        } content: {
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid")
                    .font(.system(size: 11))
                    .foregroundStyle(active ? Color.bvText : Color.bvMuted)
                    .frame(width: 16)
                Text("Workflows")
                    .font(BVFont.inter(12, weight: active ? .medium : .regular))
                    .tracking(0.05)
                    .foregroundStyle(active ? Color.bvText : Color.bvText.opacity(0.7))
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(BVFont.inter(11))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvMuted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.leading, 16)
        }
    }

    private var sortedWorkspaces: [Workspace] {
        env.workspaces.sorted { a, b in
            if a.isScratch != b.isScratch { return a.isScratch }
            return a.lastOpenedAt > b.lastOpenedAt
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Pick the folder Claude should work in."
        if panel.runModal() == .OK, let url = panel.url {
            Task { await env.addWorkspace(folderURL: url) }
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Sidebar row button

private struct SidebarRowButton<Content: View>: View {
    let isActive: Bool
    var minHeight: CGFloat = BVMetrics.sidebarRow
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: minHeight)
                .background(
                    RoundedRectangle.bv(BVRadius.control)
                        .fill(rowFill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var rowFill: Color {
        if isActive { return Color.bvSubtle }
        if hovering { return Color.bvBorder.opacity(0.5) }
        return .clear
    }
}

private struct SidebarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle.bv(BVRadius.pill)
                    .fill(configuration.isPressed ? Color.bvSubtle : Color.clear)
            )
    }
}
