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
              let relative = DateUtil.shortRelative(date) else { return "Last moved: unknown" }
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
        case .offline: return "Last seen unlocked"
        case .unknown: return "Phone status not shared"
        }
    }

    var lockIcon: String {
        switch lock {
        case .unlocked: return "lock.open.fill"
        case .locked: return "lock.fill"
        case .offline: return "lock.open"
        case .unknown: return "questionmark.circle"
        }
    }

    var lockColor: Color {
        lock == .unlocked ? .accent : .textSecondary
    }

    var lastUnlockedText: String? {
        guard let date = DateUtil.parseISO(snapshot?.activity?.unlockedAt),
              let relative = DateUtil.shortRelative(date) else { return nil }
        return "Last unlocked \(relative)"
    }

    // MARK: - Friend screen lock block
    //
    //   Locked · Last unlocked 26m ago
    //   ● updated 12 min ago
    //
    // iPhones can't stream lock events, so the screen also says how old the data is.

    /// When we last heard from the friend's phone.
    var lastSeenAt: Date? {
        if let seen = DateUtil.parseISO(snapshot?.activity?.lastSeenAt) { return seen }
        // Heartbeat within the last 3 min → as fresh as our last fetch.
        if snapshot?.activity?.isOnline == true { return snapshot?.fetchedAt }
        // Otherwise the newest thing the phone sent: a lock/unlock or a step sync.
        return [
            DateUtil.parseISO(snapshot?.activity?.unlockedAt),
            DateUtil.parseISO(snapshot?.steps?.updatedAt),
        ].compactMap { $0 }.max()
    }

    enum Freshness { case live, recent, stale }

    func freshness(now: Date = Date()) -> Freshness {
        if snapshot?.activity?.isOnline == true { return .live }
        guard let seen = lastSeenAt else { return .stale }
        switch now.timeIntervalSince(seen) {
        case ..<120: return .live
        case ..<1800: return .recent
        default: return .stale
        }
    }

    /// Lock drawn open for "unlocked" and for "last seen unlocked".
    var showsUnlocked: Bool { lock == .unlocked || lock == .offline }

    /// "Locked" / "Unlocked" / "Phone status not shared"
    var lockHeadline: String {
        switch lock {
        case .locked: return "Locked"
        case .unlocked, .offline: return "Unlocked"
        case .unknown: return "Phone status not shared"
        }
    }

    /// "Last unlocked 26m ago" (locked) or "Last seen unlocked 12m ago" (unlocked, not live).
    func lockDetail(now: Date = Date()) -> String? {
        switch lock {
        case .locked:
            guard let date = DateUtil.parseISO(snapshot?.activity?.unlockedAt),
                  let relative = DateUtil.shortRelative(date, now: now) else { return nil }
            return "Last unlocked \(relative)"
        case .offline:
            guard let relative = DateUtil.shortRelative(lastSeenAt, now: now) else { return nil }
            return "Last seen unlocked \(relative)"
        case .unlocked, .unknown:
            return nil
        }
    }

    /// "live" / "updated just now" / "updated 12 min ago"
    func updatedText(now: Date = Date()) -> String? {
        if snapshot?.activity?.isOnline == true { return "live" }
        guard let seen = lastSeenAt else { return nil }
        let minutes = Int(max(0, now.timeIntervalSince(seen)) / 60)
        switch minutes {
        case 0: return "updated just now"
        case ..<60: return "updated \(minutes) min ago"
        case ..<1440: return "updated \(minutes / 60) hr ago"
        default: return "updated \(minutes / 1440)d ago"
        }
    }

    static func distance(for steps: Int) -> String {
        let km = Double(steps) * 0.0008
        return km < 1 ? "\(Int(km * 1000)) m" : String(format: "%.1f km", km)
    }
}
