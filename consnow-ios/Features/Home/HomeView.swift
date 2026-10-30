//
//  HomeView.swift
//  Consnow
//

import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject private var tracker = StepTracker.shared
    @ObservedObject private var store = ConnectionsStore.shared
    @State private var selectedConnection: ConnectionDto?
    @State private var showAddConnection = false
    @State private var showSettings = false
    @State private var copied = false

    private var code: String { authVM.currentUser?.connectionCode ?? "------" }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header

                    if tracker.syncState == .notAuthorized {
                        motionPermissionBanner
                    }

                    StepGaugeView(steps: tracker.todaySteps)

                    statusBadges

                    codeCard

                    friendsSection
                }
                .padding(.vertical)
            }
            .refreshable {
                await tracker.refreshFromHistory()
                await tracker.syncNow(force: true)
                await store.refresh()
            }
        }
        .sheet(isPresented: $showAddConnection) {
            AddConnectionView()
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedConnection) { connection in
            ConnectionDetailView(connection: connection)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authVM)
        }
        // Refresh friends every 30s while Home is visible.
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Consnow")
                    .font(.title2).bold()
                    .foregroundColor(.accent)
                if let name = authVM.currentUser?.name {
                    Text("Hi, \(name)")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.textSecondary)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal)
    }

    private var motionPermissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step counting is off")
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)
            Text("Allow Motion & Fitness access so your friends can see your steps.")
                .font(.caption)
                .foregroundColor(.textSecondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundColor(.accent)
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.15))
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private var statusBadges: some View {
        VStack(spacing: 6) {
            if let text = syncText {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.accent.opacity(0.15))
                    .clipShape(Capsule())
            }
            if tracker.isWalking {
                Label("Walking", systemImage: "figure.walk")
                    .foregroundColor(.accent)
                    .fontWeight(.semibold)
            }
        }
    }

    private var syncText: String? {
        switch tracker.syncState {
        case .idle: return nil
        case .syncing: return "Syncing…"
        case .synced: return "Synced"
        case .offline: return "Offline · will sync later"
        case .failed: return "Sync failed · retrying"
        case .notAuthorized: return nil
        case .unavailable: return "Step counting isn't available on this device"
        }
    }

    private var codeCard: some View {
        VStack(spacing: 8) {
            Text("Your code")
                .foregroundColor(.textSecondary)
                .font(.subheadline)
            Text(code)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .textSelection(.enabled)
            Text("Share this code so someone can see your status")
                .foregroundColor(.textSecondary)
                .font(.caption)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                ShareLink(item: "Connect with me on Consnow! My code: \(code)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.accent)
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button("Add") { showAddConnection = true }
                    .foregroundColor(.accent)
            }

            if store.isOffline {
                Label("Offline — showing last known status", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            if store.connections.isEmpty {
                Text(store.hasLoaded
                     ? "No connections yet. Tap Add and enter a friend's code."
                     : "Loading…")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }

            ForEach(store.connections) { connection in
                Button {
                    selectedConnection = connection
                } label: {
                    ConnectionRow(
                        name: connection.peer.name,
                        status: PeerStatus(snapshot: store.snapshots[connection.peer.id])
                    )
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Connection Row

struct ConnectionRow: View {
    let name: String
    let status: PeerStatus

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accent)
                    .frame(width: 44, height: 44)
                Text(String(name.prefix(1)).uppercased())
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .foregroundColor(.textPrimary)
                    .fontWeight(.medium)
                if let steps = status.todaySteps, !status.notSharing {
                    Text("\(steps.formatted()) steps today")
                        .foregroundColor(.textSecondary)
                        .font(.caption)
                }
                Text(status.lastMovedText)
                    .foregroundColor(status.isWalking ? .accent : .textSecondary)
                    .font(.caption)
            }

            Spacer()

            Image(systemName: status.lockIcon)
                .foregroundColor(status.lockColor)
                .accessibilityLabel(status.lockTitle)

            Image(systemName: "chevron.right")
                .foregroundColor(.textSecondary)
                .font(.caption)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(14)
    }
}

// MARK: - Add Connection

struct AddConnectionView: View {
    @ObservedObject private var store = ConnectionsStore.shared
    @State private var code = ""
    @State private var error: String?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Add Connection")
                    .font(.title2).bold()
                    .foregroundColor(.textPrimary)

                Text("Enter your friend's 6-character code. You'll both see each other's status.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)

                TextField("ABC123", text: $code)
                    .font(.system(.title3, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding()
                    .foregroundColor(.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .onChange(of: code) { _, newValue in
                        let cleaned = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        if cleaned != newValue { code = cleaned }
                    }

                if let error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton(title: "Connect", isLoading: isLoading) {
                    Task { await connect() }
                }
                .disabled(code.count != 6)
                .opacity(code.count == 6 ? 1 : 0.5)
            }
            .padding(24)
        }
    }

    private func connect() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await store.add(code: code)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
