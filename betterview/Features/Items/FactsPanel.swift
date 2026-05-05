import SwiftUI

struct FactsPanel: View {
    @Bindable var viewModel: ItemViewModel
    @State private var draftFact = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(viewModel.item.facts.enumerated()), id: \.offset) { idx, fact in
                FactRow(text: fact) {
                    var facts = viewModel.item.facts
                    facts.remove(at: idx)
                    Task { await viewModel.updateFacts(facts) }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.bvMuted)
                TextField("Add a fact…", text: $draftFact)
                    .textFieldStyle(.plain)
                    .font(BVFont.inter(11))
                    .foregroundStyle(Color.bvText)
                    .onSubmit { add() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.bvSurface)
            )
            if viewModel.item.facts.isEmpty {
                Text("Persistent context for this item. Edits stick across sessions.")
                    .font(BVFont.inter(10))
                    .tracking(0.05)
                    .foregroundStyle(Color.bvMuted.opacity(0.7))
                    .padding(.top, 4)
            }
        }
        .padding(12)
    }

    private func add() {
        let fact = draftFact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fact.isEmpty else { return }
        var facts = viewModel.item.facts
        facts.append(fact)
        draftFact = ""
        Task { await viewModel.updateFacts(facts) }
    }
}

private struct FactRow: View {
    let text: String
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(BVFont.inter(11))
                .foregroundStyle(Color.bvMuted)
            Text(text)
                .font(BVFont.inter(11))
                .tracking(0.05)
                .foregroundStyle(Color.bvText.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.bvMuted)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .onHover { hovering = $0 }
    }
}
