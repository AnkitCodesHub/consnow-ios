//
//  ConsnowApp.swift
//  Consnow
//

import SwiftUI

@main
struct ConsnowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            case .background:
                StepTracker.shared.syncBeforeSuspend()
                LockStateTracker.shared.appEnteredBackground()
                AppDelegate.scheduleRefresh()   // keep a background refresh queued
            default: break
            }
        }
        .onChange(of: authVM.isLoggedIn) { _, loggedIn in
            if loggedIn {
                activate()
            } else {
                // Covers 401-triggered logouts too, not just the Log out button.
                StepTracker.shared.stop(resetState: true)
                LockStateTracker.shared.stop(resetState: true)
                ConnectionsStore.shared.clear()
            }
        }
    }

    /// Equivalent of Android starting StepCounterService on launch / permission grant.
    
    private func activate() {
        TokenManager.shared.reloadIfNeeded()   // session unreadable at a pre-unlock launch
        guard authVM.isLoggedIn else { return }
        StepTracker.shared.start()
        LockStateTracker.shared.appBecameActive()
        Task {
            await AppDelegate.ensureNotificationPermission()   // without it iOS drops wake-up pushes
            await TokenManager.shared.refreshIfNeeded()
            await AppDelegate.uploadPushToken()
        }
    }
}
