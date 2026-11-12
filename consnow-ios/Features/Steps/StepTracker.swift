//
//  StepTracker.swift
//  Consnow
//
//  iOS counterpart of StepCounterService + StepsRepositoryImpl.
//
//  Key differences from Android:
//  - No foreground service: iOS won't allow one. CoreMotion keeps counting
//    anyway, so we read the day's total whenever the app is active.
//  - No Room pending queue: CoreMotion IS the durable store (7 days of history).
//    If a sync fails we simply send the latest total next time.
//  - Midnight: we restart on NSCalendarDayChanged and, once per day, send
//    yesterday's final total so steps walked just before midnight aren't lost.
//

import Foundation
import Combine
import UIKit

final class StepTracker: ObservableObject {
    enum SyncState: Equatable {
        case idle
        case syncing
        case synced(Date)
        case offline
        case failed
        case notAuthorized
        case unavailable
    }

    static let shared = StepTracker()

    @Published private(set) var todaySteps = 0
    @Published private(set) var isWalking = false
    @Published private(set) var lastStepAt: Date?
    @Published private(set) var syncState: SyncState = .idle

    private let source = PedometerSource()
    private let defaults = UserDefaults.standard
    private let finalizedDayKey = "steps_finalized_day"
    private let lastStepAtKey = "steps_last_step_at"

    private var trackedDay: String?
    private var isRunning = false
    /// The sync currently running, if any (see syncNow).
    private var inFlight: Task<Bool, Never>?
    /// CoreMotion keeps 7 days of steps: back-fill at most 6 full days before today.
    static let maxBackfillDays = 6
    private var syncLoop: Task<Void, Never>?
    private var dayObserver: NSObjectProtocol?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastSent: (day: String, steps: Int, walking: Bool, at: Date)?

    private init() {
        lastStepAt = defaults.object(forKey: lastStepAtKey) as? Date
    }

    // MARK: - Lifecycle

    /// Call when the app becomes active while logged in.
    func start() {
        guard PedometerSource.isAvailable else {
            syncState = .unavailable
            return
        }
        if isRunning {
            if trackedDay != DateUtil.localDay() {
                beginTrackingToday()
            } else {
                Task { await refreshFromHistory(); await syncNow() }
            }
            return
        }
        isRunning = true
        beginTrackingToday()

        source.startActivityUpdates { [weak self] walking in
            Task { @MainActor in self?.isWalking = walking }
        }

        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.beginTrackingToday() }
        }

        startSyncLoop()
    }

    func stop(resetState: Bool = false) {
        source.stopLiveUpdates()
        source.stopActivityUpdates()
        syncLoop?.cancel()
        syncLoop = nil
        if let dayObserver {
            NotificationCenter.default.removeObserver(dayObserver)
            self.dayObserver = nil
        }
        isRunning = false

        if resetState {
            todaySteps = 0
            isWalking = false
            lastStepAt = nil
            lastSent = nil
            trackedDay = nil
            syncState = .idle
            defaults.removeObject(forKey: finalizedDayKey)
            defaults.removeObject(forKey: lastStepAtKey)
        }
    }

    /// Call when the app goes to the background: one last sync before iOS suspends us.
    func syncBeforeSuspend() {
        guard TokenManager.shared.isLoggedIn else { return }
        // Always sync, even if the previous background task (app closed a moment ago)
        // is still open; only ask iOS for extra time once.
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "StepSync") { [weak self] in
                MainActor.assumeIsolated { self?.endBackgroundTask() }
            }
        }
        Task {
            await refreshFromHistory()
            await syncNow(force: true)
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Counting

    private func beginTrackingToday() {
        let now = Date()
        let day = DateUtil.localDay(now)
        let dayStart = Calendar.current.startOfDay(for: now)

        if trackedDay != day {
            trackedDay = day
            todaySteps = 0
            lastSent = nil
        }

        source.stopLiveUpdates()
        source.startLiveUpdates(from: dayStart) { [weak self] steps, endDate in
            Task { @MainActor in self?.receiveLive(steps: steps, at: endDate, day: day) }
        }

        Task {
            await refreshFromHistory()
            await syncNow()
        }
    }

    private func receiveLive(steps: Int, at date: Date, day: String) {
        guard day == trackedDay, steps > todaySteps else { return }
        todaySteps = steps
        recordStep(at: date)
    }

    /// Reads today's total from CoreMotion (covers steps taken while the app was closed).
    func refreshFromHistory() async {
        if PedometerSource.isDenied {
            syncState = .notAuthorized
            return
        }
        let now = Date()
        let day = DateUtil.localDay(now)
        let dayStart = Calendar.current.startOfDay(for: now)

        guard let steps = await source.steps(from: dayStart, to: now) else {
            if PedometerSource.isDenied { syncState = .notAuthorized }
            return
        }
        if syncState == .notAuthorized { syncState = .idle }

        // Exact "last moved" from iOS's motion timeline (recorded even while we were asleep).
        let movement = await source.lastMovement(from: dayStart, to: now)
        if let movement {
            isWalking = movement.isWalkingNow
            if let moved = movement.lastMovedAt { recordStep(at: moved) }
        }

        guard day == trackedDay, steps > todaySteps else { return }

        todaySteps = steps
        // Fallback when the motion timeline isn't available.
        if movement?.lastMovedAt == nil,
           let estimate = await estimateLastStep(before: now, notBefore: dayStart) {
            recordStep(at: estimate)
        }
    }

    /// Called when iOS wakes the app in the background (silent push / background refresh).
    /// The UI may never have started tracking, so set up today's state and force a sync.
    /// Returns true when today's total reached the server.
    @discardableResult
    func syncFromWake() async -> Bool {
        guard TokenManager.shared.isLoggedIn, PedometerSource.isAvailable else { return false }
        let day = DateUtil.localDay()
        if trackedDay != day {
            trackedDay = day
            todaySteps = 0
            lastSent = nil
        }
        await refreshFromHistory()
        return await syncNow(force: true)
    }

    private func recordStep(at date: Date) {
        if let current = lastStepAt, current >= date { return }
        lastStepAt = date
        defaults.set(date, forKey: lastStepAtKey)
    }

    /// When steps arrive "in bulk" (app was closed), find roughly when the last one
    /// happened by checking progressively wider windows. Keeps "Last moved" honest
    /// instead of claiming the user moved "just now".
    private func estimateLastStep(before end: Date, notBefore floor: Date) async -> Date? {
        let windows: [TimeInterval] = [2, 10, 30, 60, 180, 480].map { $0 * 60 }
        var previous: TimeInterval = 0
        for window in windows {
            let start = max(end.addingTimeInterval(-window), floor)
            if let steps = await source.steps(from: start, to: end), steps > 0 {
                return end.addingTimeInterval(-previous)
            }
            if start == floor { break }
            previous = window
        }
        return nil
    }

    // MARK: - Sync (PUT /steps/sync)

    private func startSyncLoop() {
        syncLoop?.cancel()
        syncLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self?.refreshFromHistory()
                await self?.syncNow()
            }
        }
    }

    /// Sends today's total (PUT /steps/sync), then any unfinished earlier days.
    ///
    /// If a sync is already running, this waits for it. A forced sync (app going to the
    /// background, a wake-up, pull to refresh) then runs once more with the newest numbers,
    /// so it is never silently skipped. Returns true when the server has today's total.
    @discardableResult
    func syncNow(force: Bool = false) async -> Bool {
        if let running = inFlight {
            let sent = await running.value
            guard force else { return sent }
            return await syncNow(force: true)
        }
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            let sent = await self.performSync(force: force)
            self.inFlight = nil   // cleared before anyone waiting on it resumes
            return sent
        }
        inFlight = task
        // Cancelling the caller (e.g. the wake-up ran out of time) cancels the network call.
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performSync(force: Bool) async -> Bool {
        guard TokenManager.shared.isLoggedIn, let day = trackedDay else { return false }

        let now = Date()
        let steps = todaySteps
        // Same rule as the server: only "walking" if a step happened in the last 90s.
        let walking = isWalking && (lastStepAt.map { now.timeIntervalSince($0) < 90 } ?? false)

        if !force, let last = lastSent, last.day == day, last.steps == steps, last.walking == walking {
            // Nothing changed. While walking, re-send every ~50s so peers don't see us go stale.
            if !walking || now.timeIntervalSince(last.at) < 50 {
                await finalizeMissedDays()
                return true   // the server already has exactly this
            }
        }

        let dayStart = Calendar.current.startOfDay(for: now)
        let stepAt: Int64? = steps > 0
            ? lastStepAt.map { DateUtil.epochMillis(max($0, dayStart)) }
            : nil

        if case .synced = syncState {} else { syncState = .syncing }
        do {
            try await APIClient.shared.sendRaw(
                "PUT", "steps/sync",
                body: SyncStepsRequest(stepCount: steps, date: day, isActive: walking, lastStepAt: stepAt)
            )
            lastSent = (day, steps, walking, now)
            syncState = .synced(now)
        } catch APIError.offline {
            syncState = .offline
            return false
        } catch APIError.unauthorized {
            syncState = .idle
            return false
        } catch {
            if !Task.isCancelled { syncState = .failed }
            #if DEBUG
            print("StepSync failed: \(error)")
            #endif
            return false
        }

        // Today first (it's what friends look at), then any days the app missed.
        await finalizeMissedDays()
        return true
    }

    /// Sends the final total of every day since the last finished one (B12).
    ///
    /// Without this, if the app didn't run for 2+ days, every day but "yesterday" stayed
    /// stuck at whatever was synced last (steps walked later that day were never sent).
    /// CoreMotion keeps 7 days, so we go back at most 6 full days. The server never
    /// lowers a count, so re-sending is safe.
    private func finalizeMissedDays() async {
        let calendar = Calendar.current
        let pending = Self.backfillDays(
            lastDone: defaults.string(forKey: finalizedDayKey),
            todayStart: calendar.startOfDay(for: Date()),
            calendar: calendar
        )

        for start in pending {   // oldest first, so a failure leaves a clean resume point
            guard !Task.isCancelled,
                  let end = calendar.date(byAdding: .day, value: 1, to: start),
                  let steps = await source.steps(from: start, to: end) else { return }
            let key = DateUtil.localDay(start)
            if steps > 0 {
                let moved = await lastMoved(from: start, to: end)
                do {
                    try await APIClient.shared.sendRaw(
                        "PUT", "steps/sync",
                        body: SyncStepsRequest(
                            stepCount: steps, date: key, isActive: false,
                            lastStepAt: DateUtil.epochMillis(moved)
                        )
                    )
                } catch {
                    return   // offline / no time left: retry on the next sync
                }
            }
            defaults.set(key, forKey: finalizedDayKey)
        }
    }

    /// Which past days still need their final total, oldest first (as day starts).
    ///  - lastDone nil (fresh install / new sign-in): only yesterday
    ///  - otherwise every day after lastDone, at most `maxDays` back
    ///  - lastDone today or later (clock moved back): nothing
    static func backfillDays(
        lastDone: String?, todayStart: Date, calendar: Calendar, maxDays: Int = maxBackfillDays
    ) -> [Date] {
        var pending: [Date] = []   // newest first
        for back in stride(from: 1, through: maxDays, by: 1) {
            guard let start = calendar.date(byAdding: .day, value: -back, to: todayStart) else { break }
            let key = DateUtil.localDay(start)
            if let lastDone, key <= lastDone { break }   // "yyyy-MM-dd" sorts by date
            pending.append(start)
            if lastDone == nil { break }
        }
        return pending.reversed()
    }

    /// When the person last moved during a past day. Never later than the truth: the server
    /// keeps the latest "last moved" it has ever seen, so overstating it would stick.
    private func lastMoved(from start: Date, to end: Date) async -> Date {
        if let moved = await source.lastMovement(from: start, to: end)?.lastMovedAt {
            return min(moved, end.addingTimeInterval(-1))
        }
        if let estimate = await estimateLastStep(before: end, notBefore: start) {
            return min(estimate, end.addingTimeInterval(-1))
        }
        return start   // unknown: the earliest possible time, so the server keeps what it had
    }
}
