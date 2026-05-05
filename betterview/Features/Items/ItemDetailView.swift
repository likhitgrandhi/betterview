import SwiftUI

struct ItemDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let itemID: UUID
    @State private var viewModel: ItemViewModel?
    @State private var activeCanvasTab: CanvasTab = .canvas

    enum CanvasTab: String, CaseIterable, Hashable {
        case canvas = "Canvas"
        case files  = "Files"
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                Color.bvBase
                    .task { rebuildViewModel() }
            }
        }
        .id(itemID)
        .onChange(of: itemID) { _, _ in rebuildViewModel() }
        .onChange(of: env.itemsByWorkspace) { _, _ in
            Task { await viewModel?.refreshFromStore() }
        }
    }

    private func rebuildViewModel() {
        viewModel = env.viewModel(for: itemID)
    }

    private func content(viewModel: ItemViewModel) -> some View {
        VStack(spacing: 0) {
            header(viewModel: viewModel)
            BVDivider()
            HStack(spacing: 0) {
                canvasPane(viewModel: viewModel)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(Color.bvBorder)
                    .frame(width: 1)
                rail(viewModel: viewModel)
                    .frame(width: 420)
            }
        }
        .background(Color.bvBase)
        .task(id: viewModel.itemID) {
            await viewModel.markLatestSeen()
        }
        .onChange(of: viewModel.item.latestAssistantMessageID) { _, _ in
            Task { await viewModel.markLatestSeen() }
        }
    }

    // MARK: - Canvas

    private func canvasPane(viewModel: ItemViewModel) -> some View {
        VStack(spacing: 0) {
            canvasTabStrip
            ItemCanvas(item: viewModel.item)
        }
    }

    private var canvasTabStrip: some View {
        HStack(spacing: 4) {
            ForEach(CanvasTab.allCases, id: \.self) { tab in
                canvasTab(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color.bvBase)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.bvBorder)
                .frame(height: 1)
        }
    }

    private func canvasTab(_ tab: CanvasTab) -> some View {
        let isActive = activeCanvasTab == tab
        return Button {
            activeCanvasTab = tab
        } label: {
            Text(tab.rawValue)
                .font(BVFont.inter(13, weight: isActive ? .medium : .regular))
                .tracking(0.05)
                .foregroundStyle(isActive ? Color.bvText : Color.bvMuted)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    RoundedRectangle.bv(BVRadius.pill)
                        .fill(isActive ? Color.bvSubtle : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rail

    private func rail(viewModel: ItemViewModel) -> some View {
        VStack(spacing: 0) {
            if viewModel.isStartingRunner {
                startingBanner
                    .background(Color.bvSurface)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.bvBorder).frame(height: 1)
                    }
            }
            MessageListView(
                messages: viewModel.item.messages,
                emptyHint: emptyHint(for: viewModel),
                itemID: viewModel.itemID
            )
            .frame(maxHeight: .infinity)
            ComposerView(viewModel: viewModel)
        }
        .background(Color.bvBase)
    }

    private var startingBanner: some View {
        HStack(spacing: 10) {
            DotMatrixLoader(dotSize: 2.5, spacing: 4, cols: 4, rows: 2)
            Text("Starting Claude…")
                .font(BVFont.inter(13))
                .tracking(0.05)
                .foregroundStyle(Color.bvMuted)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Header

    private func header(viewModel: ItemViewModel) -> some View {
        HStack(spacing: 10) {
            backButton

            stateChip(state: viewModel.item.state)

            Text(viewModel.item.title)
                .font(BVFont.inter(13, weight: .medium))
                .tracking(0.05)
                .foregroundStyle(Color.bvText)
                .lineLimit(1)
                .padding(.leading, 4)

            if let ws = viewModel.workspace {
                workspaceChip(name: ws.name)
            }

            Spacer()

            Text(stamp(for: viewModel.item.updatedAt))
                .font(BVFont.inter(11))
                .tracking(0.05)
                .foregroundStyle(Color.bvDim)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(Color.bvBase)
    }

    private var backButton: some View {
        Button {
            env.backToList()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.bvText.opacity(0.78))
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(Color.bvSurface)
                )
                .overlay(
                    Circle().strokeBorder(Color.bvBorder, lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("All items")
    }

    private func stateChip(state: ItemState) -> some View {
        Text(state.label.uppercased())
            .font(BVFont.inter(10, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(state.dotColor)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                RoundedRectangle.bv(BVRadius.pill)
                    .fill(state.dotColor.opacity(0.12))
            )
    }

    private func workspaceChip(name: String) -> some View {
        Text(name)
            .font(BVFont.inter(11, weight: .medium))
            .tracking(0.05)
            .foregroundStyle(Color.bvMuted)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                RoundedRectangle.bv(BVRadius.pill)
                    .fill(Color.bvSurface)
            )
            .overlay(
                RoundedRectangle.bv(BVRadius.pill)
                    .strokeBorder(Color.bvBorder, lineWidth: 1)
            )
    }

    private func emptyHint(for vm: ItemViewModel) -> String {
        if let ws = vm.workspace {
            return "New item in \(ws.name)."
        }
        return "New item."
    }

    private func stamp(for date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "edited \(Int(interval / 60))m ago" }
        if interval < 86400 { return "edited \(Int(interval / 3600))h ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
