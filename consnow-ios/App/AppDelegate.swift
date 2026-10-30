//
//  AppDelegate.swift
//  Consnow
//
//  Background wake-ups. iOS suspends Consnow most of the time, so every wake is a
//  chance to send a fresh snapshot (steps, walking, last moved, locked/unlocked):
//   - silent push "status_request" (sent by the server when a friend opens your profile)
//   - background app refresh (iOS decides when; a few times a day)
//
//  Xcode setup needed (Signing & Capabilities):
//   + Push Notifications
//   + Background Modes → ✅ Remote notifications, ✅ Background fetch
//  Info tab → add BGTaskSchedulerPermittedIdentifiers = [com.consnow.ios.status-refresh]
//  (background refresh is skipped safely until that key exists)
//

import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTaskID = "com.consnow.ios.status-refresh"

    /// Silent-push wake-ups need backend support (POST /devices/apns-token + sending
    /// the push when a friend opens your profile). Off until the backend has it,
    /// so the app never calls an endpoint that doesn't exist.
    static let silentPushEnabled = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LockStateTracker.shared.start()

        // Silent pushes need no permission popup.
        if Self.silentPushEnabled {
            application.registerForRemoteNotifications()
        }

        if Self.backgroundRefreshConfigured {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: .main) { task in
                guard let task = task as? BGAppRefreshTask else { return }
                MainActor.assumeIsolated { AppDelegate.handleRefresh(task) }
            }
            Self.scheduleRefresh()
        }
        return true
    }

    // MARK: - Silent push

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard TokenManager.shared.isLoggedIn else {
            completionHandler(.noData)
            return
        }
        // iOS gives us ~30 s; both calls use short network timeouts.
        Task {
            await AppDelegate.sendFreshStatus()
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "apns_device_token")
        Task { await AppDelegate.uploadPushToken() }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed (Push Notifications capability added?): \(error)")
        #endif
    }

    // MARK: - Shared

    /// Steps + walking + last moved + lock state, all in one wake.
    static func sendFreshStatus() async {
        async let steps: Void = StepTracker.shared.syncFromWake()
        async let lock: Void = LockStateTracker.shared.reportSnapshot()
        _ = await (steps, lock)
    }

    /// Sends the APNs token so the server can wake this phone. Call again after login.
    static func uploadPushToken() async {
        guard silentPushEnabled,
              TokenManager.shared.isLoggedIn,
              let token = UserDefaults.standard.string(forKey: "apns_device_token") else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try? await APIClient.shared.sendRaw(
            "POST", "devices/apns-token",
            body: ApnsTokenRequest(token: token, environment: environment)
        )
    }

    // MARK: - Background refresh

    private static var backgroundRefreshConfigured: Bool {
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        return ids?.contains(refreshTaskID) ?? false
    }

    static func scheduleRefresh() {
        guard backgroundRefreshConfigured else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh()
        let work = Task {
            await sendFreshStatus()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
