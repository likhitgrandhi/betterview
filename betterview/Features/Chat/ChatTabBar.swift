import SwiftUI

/// Multi-item tab strip — only shown when Developer Mode is on.
struct ChatTabBar: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(openItems, id: \.id) { item in
                        tab(item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            BVDivider(axis: .vertical)
                .frame(height: 22)
                .padding(.horizontal, 8)

            Button {
                Task {
                    if let id = env.activeWorkspaceID {
                        await env.newItem(in: id)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.bvMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BVPillButtonStyle())
            .help("New Item")
            .padding(.trailing, 10)
        }
        .frame(height: 40)
        .background(Color.bvBase)
    }

    private var openItems: [Item] {
        env.openItemIDs.compactMap { id in env.item(by: id) }
    }

    private func tab(_ item: Item) -> some View {
        let isSelected = env.selectedItemID == item.id
        return HStack(spacing: 6) {
            Text(item.title)
                .font(BVFont.inter(13, weight: isSelected ? .medium : .regular))
                .tracking(0.05)
                .foregroundStyle(isSelected ? Color.bvText : Color.bvMuted)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
            Button {
                Task { await env.closeTab(item.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.bvMuted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            RoundedRectangle.bv(BVRadius.pill)
                .fill(isSelected ? Color.bvSubtle : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { env.selectedItemID = item.id }
    }
}
