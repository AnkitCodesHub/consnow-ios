//
//  LockStateTracker.swift
//  Consnow
//
//  iOS counterpart of Android's screen on/off receiver.
//
//  iOS never tells apps "the phone was locked/unlocked". What it does expose is
//  Data Protection: ~10 s after the phone locks (with a passcode), protected files
//  are encrypted and `isProtectedDataAvailable` turns false; on unlock it turns true.
//
//  So we:
//   - take a 100%-correct snapshot every time the app is awake
//     (app open, going to background, silent push, background refresh)
//   - catch the EXACT lock/unlock moment whenever our process happens to be alive
//   - report to the same endpoints Android uses:
//       PUT /activity/unlock    { occurredAt }   → isLocked = false
//       PUT /activity/lock      { occurredAt }   → isLocked = true
//       PUT /activity/heartbeat                  → isOnline (fresh) for 3 min
//
//  Note: the server stores one timestamp per transition (`unlockedAt`) and only moves
//  it forward. When locked, we send the LAST MOMENT THE PHONE WAS IN USE, so friends
//  see "Locked · Last unlocked 26m ago" and not "just now".
//

import Foundation
import Combine
import UIKit

final class LockStateTracker: ObservableObject {
    static let shared = LockStateTracker()

    @Published private(set) var isUnlocked = true
    /// Last moment we know the phone was unlocked / in use.
    @Published private(set) var lastUnlockedAt: Date?

    private let defaults = UserDefaults.standard
    private let lastUnlockedKey = "lock_last_unlocked_at"
    private let lastReportedLockedKey = "lock_last_reported_locked"
    private let lastReportedLockAtKey = "lock_last_reported_lock_at"

    private var observers: [NSObjectProtocol] = []
    private var heartbeatLoop: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundedAt: Date?
    private var lockWaiter: CheckedContinuation<Void, Never>?
    private var lastHeartbeatAt: Date?

    /// What the server currently believes (nil = unknown, e.g. fresh install).
    private var lastReportedLocked: Bool? {
        get { defaults.object(forKey: lastReportedLockedKey) as? Bool }
        set { defaults.set(newValue, forKey: lastReportedLockedKey) }
    }

    private init() {
        lastUnlockedAt = defaults.object(forKey: lastUnlockedKey) as? Date
    }

    // MARK: - Lifecycle

    /// Call once at launch (also on background launches for silent pushes).
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        // Exact UNLOCK moment (only delivered while our process is alive).
        observers.append(center.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleUnlockEvent() }
        })

        // Exact LOCK moment (~10 s after the screen locks; only while our process is alive).
        observers.append(center.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleLockEvent() }
        })
    }

    /// App came to the foreground → the phone is definitely unlocked.
    func appBecameActive() {
        guard TokenManager.shared.isLoggedIn else { return }
        backgroundedAt = nil
        markInUse(Date())
        isUnlocked = true
        Task { await reportUnlocked(force: true) }
        startHeartbeat()
    }

    /// App went to the background. Either the user switched apps (phone still unlocked)
    /// or they pressed the side button (phone locking). Wait up to ~25 s to find out.
    func appEnteredBackground() {
        guard TokenManager.shared.isLoggedIn else { return }
        stopHeartbeat()
        let now = Date()
        backgroundedAt = now
        markInUse(now)

        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LockStateCheck") { [weak self] in
            MainActor.assumeIsolated {
                self?.resumeLockWaiter()
                self?.endBackgroundTask()
            }
        }

        Task {
            await waitForLock(timeout: 25)
            // Lock event (if any) has been reported by handleLockEvent().
            // Otherwise the phone is still unlocked in another app: refresh our status.
            if UIApplication.shared.isProtectedDataAvailable {
                isUnlocked = true
                markInUse(Date())
                await reportUnlocked(force: true)
            }
            endBackgroundTask()
        }
    }

    /// Take a snapshot and report it. Used by silent pushes and background refresh.
    func reportSnapshot() async {
        guard TokenManager.shared.isLoggedIn else { return }
        if UIApplication.shared.isProtectedDataAvailable {
            isUnlocked = true
            markInUse(Date())
            await reportUnlocked(force: true)
        } else {
            isUnlocked = false
            await reportLocked()
        }
    }

    /// Call on logout.
    func stop(resetState: Bool) {
        stopHeartbeat()
        resumeLockWaiter()
        if resetState {
            lastUnlockedAt = nil
            lastHeartbeatAt = nil
            defaults.removeObject(forKey: lastUnlockedKey)
            defaults.removeObject(forKey: lastReportedLockedKey)
            defaults.removeObject(forKey: lastReportedLockAtKey)
        }
    }

    // MARK: - Exact events

    private func handleUnlockEvent() {
        guard TokenManager.shared.isLoggedIn else { return }
        isUnlocked = true
        markInUse(Date())
        Task { await reportUnlocked(force: true) }
    }

    private func handleLockEvent() {
        guard TokenManager.shared.isLoggedIn else { return }
        let now = Date()
        // If we just went to the background, the side button was most likely pressed then.
        // Otherwise iOS fires this ~10 s after the actual lock.
        let lockedAt: Date
        if let backgroundedAt, now.timeIntervalSince(backgroundedAt) < 30 {
            lockedAt = backgroundedAt
        } else {
            lockedAt = now.addingTimeInterval(-10)
        }
        markInUse(lockedAt)
        isUnlocked = false
        stopHeartbeat()
        Task {
            await reportLocked()
            resumeLockWaiter()
        }
    }

    // MARK: - Reporting

    private func reportUnlocked(force: Bool) async {
        let now = Date()
        if !force, let last = lastHeartbeatAt, now.timeIntervalSince(last) < 30 { return }

        // Only send a transition when the server thinks we're locked (or doesn't know);
        // otherwise a heartbeat is enough and avoids spamming peers with "unlocked" events.
        if lastReportedLocked != false {
            do {
                try await APIClient.shared.sendRaw(
                    "PUT", "activity/unlock",
                    body: ActivityEventRequest(occurredAt: DateUtil.epochMillis(now))
                )
                lastReportedLocked = false
            } catch {
                return   // offline: try again on the next wake
            }
        }
        do {
            try await APIClient.shared.sendRaw("PUT", "activity/heartbeat")
            lastHeartbeatAt = now
        } catch {}
    }

    private func reportLocked() async {
        // "Last unlocked" = last moment we saw the phone in use. Without it, don't guess.
        guard let lastInUse = lastUnlockedAt else { return }
        // Already told the server exactly this → don't notify peers again.
        if lastReportedLocked == true,
           let sent = defaults.object(forKey: lastReportedLockAtKey) as? Date, sent == lastInUse { return }
        do {
            try await APIClient.shared.sendRaw(
                "PUT", "activity/lock",
                body: ActivityEventRequest(occurredAt: DateUtil.epochMillis(lastInUse))
            )
            lastReportedLocked = true
            defaults.set(lastInUse, forKey: lastReportedLockAtKey)
        } catch {
            // offline: the next wake will report again
        }
    }

    // MARK: - Heartbeat (while Consnow is open)

    private func startHeartbeat() {
        heartbeatLoop?.cancel()
        heartbeatLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                await self.reportUnlocked(force: true)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatLoop?.cancel()
        heartbeatLoop = nil
    }

    // MARK: - Helpers

    private func markInUse(_ date: Date) {
        if let current = lastUnlockedAt, current >= date { return }
        lastUnlockedAt = date
        defaults.set(date, forKey: lastUnlockedKey)
    }

    private func waitForLock(timeout seconds: Double) async {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        resumeLockWaiter()   // never leave an older waiter hanging
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lockWaiter = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.resumeLockWaiter()
            }
        }
    }

    private func resumeLockWaiter() {
        lockWaiter?.resume()
        lockWaiter = nil
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
