import SwiftUI

enum ConversationTab: String, CaseIterable, Identifiable {
    case conversation, facts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .conversation: "Conversation"
        case .facts:        "Facts"
        }
    }
}

struct ConversationRail: View {
    @Bindable var viewModel: ItemViewModel
    @State private var tab: ConversationTab = .conversation

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            BVDivider()
            Group {
                switch tab {
                case .conversation:
                    conversationView
                case .facts:
                    FactsPanel(viewModel: viewModel)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            BVDivider()
            ComposerView(viewModel: viewModel)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(ConversationTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.label)
                        .font(BVFont.inter(11, weight: tab == t ? .medium : .regular))
                        .tracking(0.05)
                        .foregroundStyle(tab == t ? Color.bvText : Color.bvMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(tab == t ? Color.bvSubtle : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var conversationView: some View {
        MessageListView(messages: viewModel.item.messages)
            .frame(maxHeight: .infinity)
    }
}
