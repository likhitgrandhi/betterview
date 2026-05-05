import SwiftUI

/// Live task queue shown above the composer. Mirrors the Cursor-style
/// "N Working / M Queued" panel: rows for in-flight + pending tasks, a
/// collapsible drawer for resolved ones below.
struct QueuePanel: View {
    @Bindable var viewModel: ItemViewModel

    var body: some View {
        let pending = viewModel.item.pendingComments
        let working = pending.filter { $0.state == .working }
        let queued = pending.filter { $0.state == .queued }
        let cancelled = pending.filter { $0.state == .cancelled }
        let orphaned = pending.filter { $0.state == .orphaned }

        if pending.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                header(working: working.count, queued: queued.count, cancelled: cancelled.count + orphaned.count)
                rows(working + queued + cancelled + orphaned)
            }
            .background(
                RoundedRectangle.bv(BVRadius.card)
                    .fill(Color.bvSurface)
                    .overlay(
                        RoundedRectangle.bv(BVRadius.card)
                            .strokeBorder(Color.bvBorder, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(working: Int, queued: Int, cancelled: Int) -> some View {
        HStack(spacing: 10) {
            if working > 0 {
                statusPill(text: "\(working) Working", color: Color.bvAccent)
            }
            if queued > 0 {
                statusPill(text: "\(queued) Queued", color: Color.bvMuted)
            }
            if cancelled > 0 {
                statusPill(text: "\(cancelled) Stopped", color: .red.opacity(0.8))
            }
            Spacer()
            if working > 0 {
                Button {
                    Task { await viewModel.stopAll() }
                } label: {
                    HStack(spacing: 5) {
                        Text("Stop All").font(BVFont.inter(13)).tracking(0.05)
                        Image(systemName: "xmark").font(.system(size: 10))
                    }
                    .foregroundStyle(Color.bvText.opacity(0.78))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle.bv(BVRadius.pill)
                            .fill(Color.bvBase)
                            .overlay(
                                RoundedRectangle.bv(BVRadius.pill)
                                    .strokeBorder(Color.bvBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.bvBorder).frame(height: 1)
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(BVFont.inter(13)).tracking(0.05).foregroundStyle(Color.bvText.opacity(0.85))
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rows(_ rows: [Comment]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { comment in
                row(comment)
                if comment.id != rows.last?.id {
                    Rectangle().fill(Color.bvBorder.opacity(0.6)).frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ comment: Comment) -> some View {
        HStack(spacing: 10) {
            stateIcon(for: comment.state)
            Image(systemName: comment.anchor.iconName)
                .font(.system(size: 11))
                .foregroundStyle(Color.bvMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(comment.note.isEmpty ? "(empty)" : comment.note)
                        .font(BVFont.inter(13))
                        .tracking(0.05)
                        .foregroundStyle(Color.bvText)
                        .lineLimit(1)
                    if !comment.attachmentPaths.isEmpty {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.bvMuted)
                        Text("\(comment.attachmentPaths.count)")
                            .font(BVFont.inter(11))
                            .foregroundStyle(Color.bvMuted)
                    }
                }
                if let subtitle = subtitle(for: comment) {
                    Text(subtitle)
                        .font(BVFont.inter(11))
                        .tracking(0.05)
                        .foregroundStyle(subtitleColor(for: comment))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            trailingControls(for: comment)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func stateIcon(for state: CommentState) -> some View {
        switch state {
        case .working:
            ProgressView().controlSize(.mini).frame(width: 14, height: 14)
        case .queued:
            Circle().stroke(Color.bvMuted, lineWidth: 1).frame(width: 9, height: 9).padding(.horizontal, 2)
        case .resolved:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.bvAccent)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red.opacity(0.8))
        case .orphaned:
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        }
    }

    private func subtitle(for comment: Comment) -> String? {
        if let reason = comment.errorReason, !reason.isEmpty {
            return reason
        }
        switch comment.state {
        case .working:
            let live = viewModel.workingSubtitle
            if !live.isEmpty { return "Working: \(live)" }
            return "Working…"
        case .queued:
            let loc = comment.anchor.shortLocator
            return loc.isEmpty ? "Queued" : "Queued · \(loc)"
        case .cancelled:
            return "Cancelled — click ↻ to requeue"
        case .orphaned:
            return "Anchor lost"
        case .resolved:
            return comment.anchor.shortLocator.isEmpty ? nil : comment.anchor.shortLocator
        }
    }

    private func subtitleColor(for comment: Comment) -> Color {
        if comment.errorReason != nil { return .red.opacity(0.85) }
        switch comment.state {
        case .working: return Color.bvAccent
        case .cancelled: return .red.opacity(0.75)
        case .orphaned: return .orange
        default: return Color.bvMuted
        }
    }

    @ViewBuilder
    private func trailingControls(for comment: Comment) -> some View {
        switch comment.state {
        case .queued, .orphaned:
            Button {
                viewModel.removePending(id: comment.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Color.bvMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BVPillButtonStyle())
        case .cancelled:
            HStack(spacing: 4) {
                Button {
                    viewModel.requeueCancelled(id: comment.id)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11)).foregroundStyle(Color.bvText.opacity(0.78))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BVPillButtonStyle())
                Button {
                    viewModel.removePending(id: comment.id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Color.bvMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BVPillButtonStyle())
            }
        case .working, .resolved:
            EmptyView()
        }
    }

}
