//
//  AppDelegate.swift
//  Consnow
//
//  Background wake-ups. iOS suspends Consnow most of the time, so every wake is a
//  chance to send a fresh snapshot (steps, walking, last moved, locked/unlocked, heartbeat):
//   - silent push "status_request": the server sends it when a friend opens your profile
//     (backend: POST /profile-views → WakeService → APNs), at most once per 5 min
//   - Background App Refresh: iOS decides when, usually a few times a day,
//     more often for people who open Consnow a lot
//
//  Project setup (already in the repo):
//   - Config/Info.plist: UIBackgroundModes = fetch + remote-notification,
//     BGTaskSchedulerPermittedIdentifiers = [com.consnow.ios.status-refresh]
//   - Config/consnow-ios.entitlements: aps-environment (Push Notifications)
//  Apple Developer setup: Push Notifications enabled on the App ID com.consnow.ios,
//  and the App Store provisioning profile regenerated after that.
//

import UIKit
import BackgroundTasks
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTaskID = "com.consnow.ios.status-refresh"

    /// Silent-push wake-ups (backend: POST /devices/apns-token + WakeService).
    static let silentPushEnabled = true

    /// iOS gives ~30 s per wake; stop well before so iOS keeps trusting the app.
    static let wakeBudget: Duration = .seconds(25)

    private static let pushTokenKey = "apns_device_token"
    private static let uploadedPushTokenKey = "apns_uploaded_token_user"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LockStateTracker.shared.start()

        // Silent pushes need no permission popup.
        if Self.silentPushEnabled {
            application.registerForRemoteNotifications()
        }

        // Must be registered before launch finishes.
        if Self.backgroundRefreshConfigured {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: .main) { task in
                guard let task = task as? BGAppRefreshTask else { return }
                MainActor.assumeIsolated { AppDelegate.handleRefresh(task) }
            }
            Self.scheduleRefresh()
        } else {
            #if DEBUG
            print("⚠️ Background refresh not configured: BGTaskSchedulerPermittedIdentifiers missing from Info.plist")
            #endif
        }
        return true
    }

    // MARK: - Silent push

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        #if DEBUG
        print("📬 Silent push: \(userInfo["type"] as? String ?? "?")")
        #endif
        Task {
            let sent = await AppDelegate.sendFreshStatus(reason: "push")
            completionHandler(sent ? .newData : .noData)
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.pushTokenKey) != token {
            defaults.set(token, forKey: Self.pushTokenKey)
            defaults.removeObject(forKey: Self.uploadedPushTokenKey)   // new token: upload again
        }
        Task { await AppDelegate.uploadPushToken() }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed (Push Notifications capability / profile?): \(error)")
        #endif
    }

    // MARK: - Shared

    /// Steps + walking + last moved + lock state + heartbeat, all in one wake.
    /// Returns true when something reached the server. Never runs past `wakeBudget`.
    @discardableResult
    static func sendFreshStatus(reason: String) async -> Bool {
        // After a reboot iOS can wake us before the first unlock, when the session can't
        // be read yet. Try again now; if it's still locked away, there's nothing to send.
        TokenManager.shared.reloadIfNeeded()
        guard TokenManager.shared.isLoggedIn else { return false }

        // Race the work against the time budget. Structured, so cancelling (budget hit or
        // iOS expiring the task) also cancels the network calls in flight.
        let sent = await withTaskGroup(of: Bool?.self) { group -> Bool in
            group.addTask { @MainActor in
                // Steps and lock state side by side.
                await withTaskGroup(of: Bool.self) { inner -> Bool in
                    inner.addTask { @MainActor in await StepTracker.shared.syncFromWake() }
                    inner.addTask { @MainActor in
                        await LockStateTracker.shared.reportSnapshot()
                        return false
                    }
                    var stepsSent = false
                    for await result in inner { stepsSent = stepsSent || result }
                    return stepsSent
                }
            }
            group.addTask {
                try? await Task.sleep(for: AppDelegate.wakeBudget)
                return nil   // budget used up
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? false
        }
        #if DEBUG
        print("⏰ Wake (\(reason)) finished, steps sent: \(sent)")
        #endif
        return sent
    }

    /// Sends the APNs token so the server can wake this phone. Call again after login.
    static func uploadPushToken() async {
        let defaults = UserDefaults.standard
        guard silentPushEnabled,
              TokenManager.shared.isLoggedIn,
              let userId = TokenManager.shared.user?.id,
              let token = defaults.string(forKey: pushTokenKey) else { return }
        // Already uploaded this token for this account.
        if defaults.string(forKey: uploadedPushTokenKey) == "\(userId):\(token)" { return }
        do {
            try await APIClient.shared.sendRaw(
                "POST", "devices/apns-token",
                body: ApnsTokenRequest(token: token, environment: apnsEnvironment)
            )
            defaults.set("\(userId):\(token)", forKey: uploadedPushTokenKey)
        } catch {
            // offline: retried on the next launch / login
        }
    }

    /// iOS throws away even silent wake-up pushes when the app has no notification
    /// permission (Apple's delivery log: "discarded because the user disabled
    /// notifications for the app"). Ask for *provisional* permission: no popup, nothing
    /// shown to the user, but the app counts as allowed so wake-ups get through.
    /// If the user turned notifications off themselves, we leave that alone (the Home
    /// banner explains it).
    static func ensureNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.provisional, .alert, .badge, .sound])
        #if DEBUG
        let after = await center.notificationSettings()
        print("🔔 Notification permission: \(after.authorizationStatus.rawValue) (3 = provisional)")
        #endif
    }

    /// On sign-out: stop the server from waking this phone for that account.
    static func clearPushTokenOnServer() async {
        guard silentPushEnabled, TokenManager.shared.isLoggedIn else { return }
        _ = try? await APIClient.shared.sendRaw("DELETE", "devices/apns-token", timeout: 5)
        UserDefaults.standard.removeObject(forKey: uploadedPushTokenKey)
    }

    /// "sandbox" for builds installed from Xcode, "production" for TestFlight / App Store.
    /// Development-signed builds carry an embedded.mobileprovision with
    /// aps-environment = development; App Store / TestFlight builds don't carry one.
    static let apnsEnvironment: String = {
        #if targetEnvironment(simulator)
        return "sandbox"   // Simulator tokens are always sandbox tokens
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1) else { return "production" }
        return apnsEnvironment(fromProvisioningProfile: text)
        #endif
    }()

    /// "sandbox" when the profile grants aps-environment = development, else "production".
    static func apnsEnvironment(fromProvisioningProfile text: String) -> String {
        let compact = text.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        return compact.contains("<key>aps-environment</key><string>development</string>") ? "sandbox" : "production"
    }

    // MARK: - Background refresh

    private static var backgroundRefreshConfigured: Bool {
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        return ids?.contains(refreshTaskID) ?? false
    }

    /// Ask iOS for the next background refresh. Each request is used once, so this is
    /// called at launch, every time the app goes to the background, and after each run.
    static func scheduleRefresh() {
        guard backgroundRefreshConfigured else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            // Fails on the Simulator (unsupported) and when Background App Refresh is off.
            print("BG refresh not scheduled: \(error)")
            #endif
        }
    }

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh()   // keep the chain going even if this run is cut short
        let work = Task {
            let sent = await AppDelegate.sendFreshStatus(reason: "refresh")
            task.setTaskCompleted(success: sent)
        }
        // Out of time: cancel; the work then returns and reports completion above.
        task.expirationHandler = {
            work.cancel()
        }
    }
}
