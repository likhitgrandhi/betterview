import SwiftUI

struct CommandPalette: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var highlightedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            field
            if !filteredItems.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty {
                BVDivider()
                results
            }
        }
        .background(
            RoundedRectangle.bv(BVRadius.sheet)
                .fill(Color.bvBase)
                .overlay(
                    RoundedRectangle.bv(BVRadius.sheet)
                        .strokeBorder(Color.bvBorder, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 24, x: 0, y: 8)
        .frame(width: 560)
        .onAppear {
            query = ""
            highlightedIndex = 0
            fieldFocused = true
        }
        .onChange(of: query) { _, _ in
            highlightedIndex = 0
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.bvMuted)
            TextField("Search items, fire an action…", text: $query)
                .textFieldStyle(.plain)
                .font(BVFont.inter(13))
                .foregroundStyle(Color.bvText)
                .focused($fieldFocused)
                .onSubmit { activateHighlighted() }
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.bvMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BVPillButtonStyle())
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if filteredItems.isEmpty {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        createRow
                    }
                } else {
                    sectionHeader(query.isEmpty ? "RECENT" : "ITEMS")
                    ForEach(Array(filteredItems.enumerated()), id: \.offset) { idx, item in
                        resultRow(item: item, isHighlighted: idx == highlightedIndex)
                            .onTapGesture { activate(item: item) }
                            .onHover { if $0 { highlightedIndex = idx } }
                    }
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        BVDivider().padding(.vertical, 4)
                        createRow
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 360)
        .scrollContentBackground(.hidden)
    }

    private func sectionHeader(_ s: String) -> some View {
        HStack {
            Text(s)
                .font(BVFont.inter(10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Color.bvMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func resultRow(item: Item, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.state.dotColor)
                .frame(width: 7, height: 7)
            Image(systemName: item.type.defaultIconName)
                .font(.system(size: 11))
                .foregroundStyle(Color.bvMuted)
                .frame(width: 16)
            Text(item.title)
                .font(BVFont.inter(13, weight: .medium))
                .tracking(0.05)
                .foregroundStyle(Color.bvText)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let ws = env.workspaces.first(where: { $0.id == item.workspaceID }) {
                Text(ws.name)
                    .font(BVFont.inter(11))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvMuted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle.bv(BVRadius.control)
                .fill(isHighlighted ? Color.bvSurface : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var createRow: some View {
        Button {
            createFromQuery()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.bvAccent)
                    .frame(width: 16)
                Text("Create new item from this query")
                    .font(BVFont.inter(13))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle.bv(BVRadius.control)
                    .fill(filteredItems.isEmpty ? Color.bvSurface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredItems: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = env.itemsByWorkspace.values.flatMap { $0 }
            .sorted { $0.updatedAt > $1.updatedAt }
        if q.isEmpty {
            return Array(all.prefix(10))
        }
        return all.filter { item in
            item.title.lowercased().contains(q)
                || item.lastMessagePreview.lowercased().contains(q)
        }
        .prefix(20)
        .map { $0 }
    }

    private func activateHighlighted() {
        if !filteredItems.isEmpty {
            activate(item: filteredItems[min(highlightedIndex, filteredItems.count - 1)])
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            createFromQuery()
        }
    }

    private func activate(item: Item) {
        env.openItem(item.id)
        if case .all = env.listScope {
            Task { await env.setActiveWorkspace(item.workspaceID) }
        }
        isPresented = false
    }

    private func createFromQuery() {
        let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let workspaceID: UUID = {
            switch env.listScope {
            case .workspace(let id), .workflows(let id): return id
            case .all:
                if let active = env.activeWorkspaceID { return active }
                return env.workspaces.first?.id ?? UUID()
            }
        }()
        Task {
            let item = await env.newItem(in: workspaceID)
            env.openItem(item.id)
            if let vm = env.viewModel(for: item.id) {
                vm.enqueueFreeform(prompt)
            }
        }
        isPresented = false
    }
}
