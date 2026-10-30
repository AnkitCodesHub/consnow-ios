//
//  PedometerSource.swift
//  Consnow
//
//  Thin wrapper over CoreMotion. Deliberately `nonisolated`: CoreMotion calls
//  its handlers on background queues, and the project's default isolation is
//  MainActor — keeping the callbacks out of MainActor avoids runtime isolation traps.
//
//  Unlike Android's sensor + foreground service, iOS counts steps in the motion
//  coprocessor all the time (and keeps 7 days of history), so the app never has
//  to be running to "catch" steps — it just asks for the total when it wakes up.
//

import Foundation
import CoreMotion

nonisolated final class PedometerSource: @unchecked Sendable {
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private let activityQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "consnow.motion-activity"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    static var isDenied: Bool {
        let status = CMPedometer.authorizationStatus()
        return status == .denied || status == .restricted
    }

    /// Total steps in [start, end). Returns nil on error (e.g. permission denied).
    /// The first call shows the "Motion & Fitness" permission prompt.
    func steps(from start: Date, to end: Date) async -> Int? {
        guard end > start else { return 0 }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data?.numberOfSteps.intValue ?? 0)
                }
            }
        }
    }

    /// Live cumulative steps since `start`, delivered while the app is running.
    func startLiveUpdates(from start: Date, onUpdate: @escaping @Sendable (Int, Date) -> Void) {
        pedometer.startUpdates(from: start) { data, error in
            guard let data, error == nil else { return }
            onUpdate(data.numberOfSteps.intValue, data.endDate)
        }
    }

    func stopLiveUpdates() {
        pedometer.stopUpdates()
    }

    /// Walking/running detection — the iOS equivalent of the Android "isActive" flag.
    func startActivityUpdates(onChange: @escaping @Sendable (Bool) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: activityQueue) { activity in
            guard let activity else { return }
            onChange(activity.walking || activity.running)
        }
    }

    func stopActivityUpdates() {
        activityManager.stopActivityUpdates()
    }

    /// Result of reading iOS's motion timeline.
    struct Movement: Sendable {
        /// The newest motion state is walking/running.
        let isWalkingNow: Bool
        /// When they last stopped walking/running (`end` if still walking). nil = no movement in the window.
        let lastMovedAt: Date?
    }

    /// Reads the motion timeline iOS records in the background (even while the app is asleep
    /// or the phone is locked) and finds the exact moment the person last moved.
    /// Returns nil if activity data isn't available or permission is denied.
    func lastMovement(from start: Date, to end: Date) async -> Movement? {
        guard CMMotionActivityManager.isActivityAvailable(), end > start else { return nil }
        let activities: [CMMotionActivity]? = await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: start, to: end, to: activityQueue) { activities, error in
                continuation.resume(returning: error == nil ? (activities ?? []) : nil)
            }
        }
        guard let activities else { return nil }

        // The list is a sequence of state changes; each lasts until the next one starts.
        func isMoving(_ activity: CMMotionActivity) -> Bool {
            (activity.walking || activity.running) && activity.confidence != .low
        }
        guard let index = activities.lastIndex(where: isMoving) else {
            return Movement(isWalkingNow: false, lastMovedAt: nil)
        }
        if index == activities.count - 1 {
            return Movement(isWalkingNow: true, lastMovedAt: end)
        }
        let stoppedAt = min(activities[index + 1].startDate, end)
        return Movement(isWalkingNow: false, lastMovedAt: stoppedAt)
    }
}
