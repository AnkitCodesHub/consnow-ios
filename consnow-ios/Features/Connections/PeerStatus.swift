//
//  PeerStatus.swift
//  Consnow
//
//  Turns a PeerSnapshot into display text, shared by the list row and detail screen.
//

import SwiftUI

struct PeerStatus {
    let snapshot: PeerSnapshot?

    /// Today's steps (a cached value from an earlier day counts as 0).
    var todaySteps: Int? {
        guard let steps = snapshot?.steps else { return nil }
        return steps.date == DateUtil.localDay() ? steps.stepCount : 0
    }

    var isWalking: Bool {
        guard let steps = snapshot?.steps, steps.date == DateUtil.localDay() else { return false }
        return steps.isActive
    }

    var notSharing: Bool { snapshot?.notSharing ?? false }

    var lastMovedText: String {
        if notSharing { return "Not sharing steps" }
        if isWalking { return "Walking now" }
        guard let date = DateUtil.parseISO(snapshot?.steps?.lastActiveAt),
              let relative = DateUtil.relative(date) else { return "Last moved: unknown" }
        return "Last moved \(relative)"
    }

    enum Lock { case unlocked, locked, offline, unknown }

    var lock: Lock {
        guard let activity = snapshot?.activity else { return .unknown }
        // No unlock ever recorded → this friend's phone doesn't report lock status
        // (e.g. an iPhone). The server defaults that case to "locked", which would mislead.
        guard activity.unlockedAt != nil else { return .unknown }
        if activity.isLocked { return .locked }
        return activity.isOnline ? .unlocked : .offline
    }

    var lockTitle: String {
        switch lock {
        case .unlocked: return "Phone unlocked"
        case .locked: return "Phone locked"
        case .offline: return "Offline"
        case .unknown: return "Phone status not shared"
        }
    }

    var lockIcon: String {
        switch lock {
        case .unlocked: return "lock.open.fill"
        case .locked: return "lock.fill"
        case .offline: return "wifi.slash"
        case .unknown: return "questionmark.circle"
        }
    }

    var lockColor: Color {
        lock == .unlocked ? .accent : .textSecondary
    }

    var lastUnlockedText: String? {
        guard let date = DateUtil.parseISO(snapshot?.activity?.unlockedAt),
              let relative = DateUtil.relative(date) else { return nil }
        return "Last unlocked \(relative)"
    }

    static func distance(for steps: Int) -> String {
        let km = Double(steps) * 0.0008
        return km < 1 ? "\(Int(km * 1000)) m" : String(format: "%.1f km", km)
    }
}
