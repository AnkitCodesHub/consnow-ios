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

                    // Lock status card
                    HStack(spacing: 14) {
                        Image(systemName: status.lockIcon)
                            .font(.title2)
                            .foregroundColor(status.lockColor)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.lockTitle)
                                .foregroundColor(.textPrimary)
                                .fontWeight(.medium)
                            if let unlocked = status.lastUnlockedText {
                                Text(unlocked)
                                    .foregroundColor(.textSecondary)
                                    .font(.caption)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.cardBackground)
                    .cornerRadius(14)
                    .padding(.horizontal)

                    Button {
                        Task { await refresh() }
                    } label: {
                        Text(isRefreshing ? "Refreshing..." : "Tap to refresh")
                            .foregroundColor(.accent)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .overlay(Capsule().stroke(Color.accent, lineWidth: 1))
                    }
                    .disabled(isRefreshing)

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
