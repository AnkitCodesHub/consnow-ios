//
//  ConnectionDetailView.swift
//  Consnow
//

import SwiftUI

struct ConnectionDetailView: View {
    let connection: ConnectionDto
    @ObservedObject private var store = ConnectionsStore.shared
    @State private var isRefreshing = false

    private var status: PeerStatus { PeerStatus(snapshot: store.snapshots[connection.peer.id]) }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)

                    StepGaugeView(
                        steps: status.todaySteps ?? 0,
                        title: connection.peer.name,
                        size: 260,
                        placeholder: status.todaySteps == nil || status.notSharing
                    )

                    VStack(spacing: 6) {
                        if status.isWalking {
                            Label("Walking now", systemImage: "figure.walk")
                                .foregroundColor(.accent)
                                .fontWeight(.semibold)
                        } else {
                            Text(status.lastMovedText)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Button {
                        Task { await refresh() }
                    } label: {
                        HStack(spacing: 8) {
                            if isRefreshing {
                                ProgressView().controlSize(.small).tint(.accent)
                            }
                            Text(isRefreshing ? "Refreshing..." : "Tap to refresh")
                        }
                        .foregroundColor(.accent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.accent.opacity(0.12)))
                    }
                    .disabled(isRefreshing)
                    .animation(.easeInOut(duration: 0.2), value: isRefreshing)

                    // Re-render every 15 s so "26m ago" keeps counting between fetches.
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        LockStatusBlock(status: status, now: context.date, isRefreshing: isRefreshing)
                    }
                    .padding(.top, 24)

                    if store.isOffline {
                        Text("Offline — showing last known status")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        // Auto-refresh every 15s while this screen is open (until WebSocket push is added).
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        await store.refreshPeer(connection.peer.id)
        isRefreshing = false
    }
}

// MARK: - Lock block

/// (animated lock)
/// Locked · Last unlocked 26m ago
/// ● updated 12 min ago
private struct LockStatusBlock: View {
    let status: PeerStatus
    let now: Date
    let isRefreshing: Bool

    var body: some View {
        VStack(spacing: 10) {
            if status.lock == .unknown {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.textSecondary)
                    .padding(.bottom, 4)
            } else {
                AnimatedLockIcon(
                    isUnlocked: status.showsUnlocked,
                    isLive: freshness == .live,
                    isStale: freshness == .stale,
                    size: 96
                )
            }

            headline
                .font(.system(size: 24, design: .rounded))
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: status.lockHeadline)
                .padding(.horizontal)

            if let updated = status.updatedText(now: now) {
                HStack(spacing: 6) {
                    Circle().fill(dotColor).frame(width: 6, height: 6)
                    Text(updated)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.textSecondary)
                        .contentTransition(.numericText())
                }
                .animation(.easeInOut(duration: 0.3), value: updated)
            }
        }
    }

    private var freshness: PeerStatus.Freshness { status.freshness(now: now) }

    /// "Locked" bold + " · Last unlocked 26m ago" lighter.
    private var headline: Text {
        let title = Text(status.lockHeadline)
            .fontWeight(.bold)
            .foregroundColor(status.lock == .unknown ? .textSecondary : .textPrimary)
        guard let detail = status.lockDetail(now: now) else { return title }
        let rest = Text(" · \(detail)")
            .fontWeight(.semibold)
            .foregroundColor(.textPrimary.opacity(0.75))
        return Text("\(title)\(rest)")
    }

    private var dotColor: Color {
        switch freshness {
        case .live: return .accent
        case .recent: return .textSecondary
        case .stale: return .warning
        }
    }
}
