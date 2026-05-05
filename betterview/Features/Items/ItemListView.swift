import SwiftUI

struct ItemListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pendingDelete: Item?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                MagicPromptBox()
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                groupedSections
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.bvBase)
        .confirmationDialog(
            "Delete this item?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) {
                Task { await env.deleteItem(item.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { item in
            Text("\"\(item.title)\" and its session history will be removed.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(scopeTitle)
                    .font(BVFont.inter(22, weight: .medium))
                    .tracking(0.02)
                    .foregroundStyle(Color.bvText)
                Spacer()
                Text(rightStamp)
                    .font(BVFont.inter(13))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvMuted)
            }
            Text("\(visibleCount) items · sorted by what needs you")
                .font(BVFont.inter(13))
                .tracking(0.05)
                .foregroundStyle(Color.bvMuted)
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var groupedSections: some View {
        ForEach(groupedStates, id: \.self) { state in
            section(for: state, items: grouped[state] ?? [])
        }
    }

    private func section(for state: ItemState, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(state.groupTitle) · \(items.count)")
                    .font(BVFont.inter(11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.bvMuted)
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 6)

            VStack(spacing: 2) {
                ForEach(items) { item in
                    ItemRow(
                        item: item,
                        workspaceName: workspaceName(for: item),
                        isSelected: env.selectedItemID == item.id,
                        onOpen: { env.openItem(item.id) },
                        onDelete: { pendingDelete = item }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var grouped: [ItemState: [Item]] {
        Dictionary(grouping: env.visibleItems.sorted { $0.updatedAt > $1.updatedAt }, by: \.state)
    }

    private var groupedStates: [ItemState] {
        grouped.keys.sorted { $0.groupOrder < $1.groupOrder }
    }

    private var visibleCount: Int {
        env.visibleItems.count
    }

    private var scopeTitle: String {
        switch env.listScope {
        case .all: return "All items"
        case .workspace(let id), .workflows(let id):
            return env.workspaces.first(where: { $0.id == id })?.name ?? "Workspace"
        }
    }

    private var rightStamp: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: .now)
    }

    private func workspaceName(for item: Item) -> String? {
        guard case .all = env.listScope else { return nil }
        return env.workspaces.first { $0.id == item.workspaceID }?.name
    }
}
