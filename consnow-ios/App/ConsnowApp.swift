//
//  ConsnowApp.swift
//  Consnow
//

import SwiftUI

@main
struct ConsnowApp: App {
    @StateObject private var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authVM)
                .preferredColorScheme(.dark)
                .tint(Color.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLogin = true

    var body: some View {
        Group {
            if authVM.isLoggedIn {
                HomeView()
            } else if showLogin {
                LoginView(showLogin: $showLogin)
            } else {
                RegisterView(showLogin: $showLogin)
            }
        }
        .task {
            if scenePhase == .active { activate() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: activate()
            case .background: StepTracker.shared.syncBeforeSuspend()
            default: break
            }
        }
        .onChange(of: authVM.isLoggedIn) { _, loggedIn in
            if loggedIn {
                activate()
            } else {
                // Covers 401-triggered logouts too, not just the Log out button.
                StepTracker.shared.stop(resetState: true)
                ConnectionsStore.shared.clear()
            }
        }
    }

    /// Equivalent of Android starting StepCounterService on launch / permission grant.
    private func activate() {
        guard authVM.isLoggedIn else { return }
        StepTracker.shared.start()
        Task { await TokenManager.shared.refreshIfNeeded() }
    }
}
