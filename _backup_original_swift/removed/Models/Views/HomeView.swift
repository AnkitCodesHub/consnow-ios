//
//  HomeView.swift
//  MyApp
//
//  Created by Ankit Raj on 12/10/26.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var vm = HomeViewModel()
    @State private var selectedConnection: ConnectionResponse? = nil

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // Step gauge
                    StepGaugeView(steps: vm.todaySteps, isActive: vm.isActive)

                    // Synced badge + Walking status
                    VStack(spacing: 6) {
                        Text("Synced")
                            .font(.caption)
                            .foregroundColor(.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Color.accent.opacity(0.15))
                            .clipShape(Capsule())

                        if vm.isActive {
                            HStack(spacing: 4) {
                                Text("🚶")
                                Text("Walking")
                                    .foregroundColor(.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                    }

                    // Connection code
                    VStack(spacing: 4) {
                        Text("Your code")
                            .foregroundColor(.textSecondary)
                            .font(.subheadline)
                        Text(vm.connectionCode)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("Share this code so someone can see your steps")
                            .foregroundColor(.textSecondary)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }

                    // Connected users
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Connected")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Button("Add") {
                                vm.showAddConnection = true
                            }
                            .foregroundColor(.accent)
                        }

                        ForEach(vm.connections) { connection in
                            Button {
                                selectedConnection = connection
                            } label: {
                                ConnectionRow(connection: connection)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .sheet(isPresented: $vm.showAddConnection) {
            AddConnectionView(vm: vm)
        }
        .sheet(item: $selectedConnection) { connection in
            ConnectionDetailView(connection: connection)
        }
        .task {
            await vm.load()
        }
    }
}

// MARK: - Step Gauge
struct StepGaugeView: View {
    let steps: Int
    let isActive: Bool

    var progress: Double {
        min(Double(steps) / 10000.0, 1.0)
    }

    var distanceKm: String {
        let km = Double(steps) * 0.0008
        if km < 1 {
            return "\(Int(km * 1000)) m"
        }
        return String(format: "%.1f km", km)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.cardBackground)
                .frame(width: 220, height: 220)

            // Background arc
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(90))

            // Progress arc
            Circle()
                .trim(from: 0.15, to: 0.15 + (0.70 * progress))
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(90))
                .animation(.easeOut, value: progress)

            VStack(spacing: 2) {
                Text("🚶")
                    .font(.title2)
                Text("\(steps)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(distanceKm)
                    .foregroundColor(.textSecondary)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Connection Row
struct ConnectionRow: View {
    let connection: ConnectionResponse

    var body: some View {
        HStack(spacing: 14) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(Color.accent)
                    .frame(width: 44, height: 44)
                Text(String(connection.name.prefix(1)).uppercased())
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .foregroundColor(.textPrimary)
                    .fontWeight(.medium)
                Text("Sharing steps")
                    .foregroundColor(.textSecondary)
                    .font(.caption)
            }

            Spacer()

            Image(systemName: "arrow.right")
                .foregroundColor(.textSecondary)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(14)
    }
}

// MARK: - Add Connection
struct AddConnectionView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var code = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Add Connection")
                    .font(.title2).bold()
                    .foregroundColor(.textPrimary)

                TextField("Enter connection code", text: $code)
                    .padding()
                    .foregroundColor(.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                Button {
                    Task {
                        await vm.addConnection(code: code)
                        dismiss()
                    }
                } label: {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accent)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
            }
            .padding(24)
        }
    }
}
