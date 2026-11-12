//
//  BackgroundStatusBanner.swift
//  Consnow
//
//  Tells the user when iOS won't let Consnow update in the background, so friends
//  would see old steps / lock status: Background App Refresh off, or Low Power Mode on.
//

import SwiftUI
import UIKit
import Combine
import UserNotifications

/// Watches the two iPhone settings that stop background updates.
final class BackgroundStatusMonitor: ObservableObject {
    static let shared = BackgroundStatusMonitor()

    enum Problem: Equatable { case notificationsOff, refreshOff, refreshRestricted, lowPower }

    @Published private(set) var problem: Problem?
    private var notificationsDenied = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        update()
        let center = NotificationCenter.default
        Publishers.MergeMany(
            center.publisher(for: UIApplication.backgroundRefreshStatusDidChangeNotification),
            center.publisher(for: .NSProcessInfoPowerStateDidChange),
            center.publisher(for: UIApplication.didBecomeActiveNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.update() }
        .store(in: &cancellables)
    }

    private func update() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsDenied = settings.authorizationStatus == .denied
            apply()
        }
        apply()
    }

    private func apply() {
        if notificationsDenied { problem = .notificationsOff; return }
        switch UIApplication.shared.backgroundRefreshStatus {
        case .denied: problem = .refreshOff
        case .restricted: problem = .refreshRestricted
        default: problem = ProcessInfo.processInfo.isLowPowerModeEnabled ? .lowPower : nil
        }
    }
}

struct BackgroundStatusBanner: View {
    let problem: BackgroundStatusMonitor.Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)
            Text(message)
                .font(.caption)
                .foregroundColor(.textSecondary)
            if problem == .refreshOff || problem == .notificationsOff {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundColor(.accent)
                .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.warning.opacity(0.15))
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private var title: String {
        switch problem {
        case .notificationsOff: return "Notifications are off"
        case .refreshOff, .refreshRestricted: return "Background updates are off"
        case .lowPower: return "Low Power Mode is on"
        }
    }

    private var message: String {
        switch problem {
        case .notificationsOff:
            return "Turn on notifications for Consnow so it can update your status when friends check on you, even while the app is closed."
        case .refreshOff:
            return "Turn on Background App Refresh for Consnow so friends see your latest steps and status when the app is closed."
        case .refreshRestricted:
            return "Background App Refresh is blocked on this iPhone (Screen Time or a profile), so friends only see your status when Consnow is open."
        case .lowPower:
            return "iOS pauses background updates in Low Power Mode, so friends may see your status a little late."
        }
    }
}
