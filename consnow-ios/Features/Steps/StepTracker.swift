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
    private var isSyncing = false
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
        guard TokenManager.shared.isLoggedIn, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "StepSync") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
        Task {
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
        guard day == trackedDay, steps > todaySteps else { return }

        todaySteps = steps
        if let estimate = await estimateLastStep(before: now, notBefore: dayStart) {
            recordStep(at: estimate)
        }
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

    func syncNow(force: Bool = false) async {
        guard TokenManager.shared.isLoggedIn, !isSyncing, let day = trackedDay else { return }
        isSyncing = true
        defer { isSyncing = false }

        await finalizeYesterdayIfNeeded()

        let now = Date()
        let steps = todaySteps
        // Same rule as the server: only "walking" if a step happened in the last 90s.
        let walking = isWalking && (lastStepAt.map { now.timeIntervalSince($0) < 90 } ?? false)

        if !force, let last = lastSent, last.day == day, last.steps == steps, last.walking == walking {
            // Nothing changed. While walking, re-send every ~50s so peers don't see us go stale.
            if !walking || now.timeIntervalSince(last.at) < 50 { return }
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
        } catch APIError.unauthorized {
            syncState = .idle
        } catch {
            syncState = .failed
            #if DEBUG
            print("StepSync failed: \(error)")
            #endif
        }
    }

    /// Once per day, send yesterday's final total (steps walked before midnight
    /// that never got synced). The server never lowers a count, so this is safe.
    private func finalizeYesterdayIfNeeded() async {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return }
        let yesterday = DateUtil.localDay(yesterdayStart)
        guard defaults.string(forKey: finalizedDayKey) != yesterday else { return }
        guard let steps = await source.steps(from: yesterdayStart, to: todayStart) else { return }

        do {
            if steps > 0 {
                let lastStep = await estimateLastStep(before: todayStart, notBefore: yesterdayStart)
                    ?? todayStart.addingTimeInterval(-1)
                try await APIClient.shared.sendRaw(
                    "PUT", "steps/sync",
                    body: SyncStepsRequest(
                        stepCount: steps, date: yesterday, isActive: false,
                        lastStepAt: DateUtil.epochMillis(lastStep)
                    )
                )
            }
            defaults.set(yesterday, forKey: finalizedDayKey)
        } catch {
            // retry on the next sync
        }
    }
}
