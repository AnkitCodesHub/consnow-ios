//
//  ConnectionDetailView.swift
//  MyApp
//
//  Created by Ankit Raj on 12/10/26.
//
import SwiftUI

struct ConnectionDetailView: View {
    let connection: ConnectionResponse
    @State private var steps: Int = 0
    @State private var lastActive: String = ""
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss

    var distanceKm: String {
        let km = Double(steps) * 0.0008
        return String(format: "%.1f km", km)
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Big gauge
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.cardBackground)
                        .frame(width: 260, height: 260)

                    Circle()
                        .trim(from: 0.15, to: 0.85)
                        .stroke(Color.white.opacity(0.1),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(90))

                    Circle()
                        .trim(from: 0.15, to: 0.15 + (0.70 * min(Double(steps) / 10000.0, 1.0)))
                        .stroke(Color.accent,
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(90))
                        .animation(.easeOut, value: steps)

                    VStack(spacing: 4) {
                        Text(connection.name)
                            .foregroundColor(.textSecondary)
                            .font(.subheadline)
                        Text("🚶")
                            .font(.title2)
                        Text(steps == 0 ? "---" : "\(steps)")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if steps > 0 {
                            Text(distanceKm)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }

                if !lastActive.isEmpty {
                    Text("Last moved \(lastActive)")
                        .foregroundColor(.textSecondary)
                }

                Button {
                    Task { await refresh() }
                } label: {
                    Text(isLoading ? "Refreshing..." : "Tap to refresh")
                        .foregroundColor(.accent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .overlay(
                            Capsule().stroke(Color.accent, lineWidth: 1)
                        )
                }

                Spacer()
            }
        }
        .task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        // You'll wire this to your API once ConnectionDetailViewModel is built
        // For now shows the data from the connection object
        steps = connection.stepCount ?? 0
        lastActive = connection.lastActiveAt ?? ""
        isLoading = false
    }
}
