//
//  ConsnowLogicTests.swift
//  consnow-iosTests
//
//  Unit tests for the logic behind Seen by, background back-fill, friend status,
//  dates, Keychain (B8) and the APNs environment (B2).
//  Run: Product → Test (⌘U) on an iOS Simulator.
//

import XCTest
@testable import consnow_ios

// MARK: - Seen by

@MainActor
final class WatchersTests: XCTestCase {
    func testFirstNameKeepsOnlyTheFirstWord() {
        XCTAssertEqual(watcherFirstName("Sangita Pandey"), "Sangita")
        XCTAssertEqual(watcherFirstName("  Ankit  "), "Ankit")
        XCTAssertEqual(watcherFirstName("Aakancha\tPandey"), "Aakancha")
        XCTAssertEqual(watcherFirstName("Vishwakant"), "Vishwakant")
        XCTAssertEqual(watcherFirstName(""), "")
        XCTAssertEqual(watcherFirstName("   "), "")
    }

    func testPopupShowsNewestThreeOnly() {
        let now = Date()
        let all = (0..<5).map { ProfileWatcher(name: "F\($0)", openedAt: now.addingTimeInterval(-Double($0) * 60)) }
        let shown = visibleWatchers(all.shuffled())
        XCTAssertEqual(shown.map(\.name), ["F0", "F1", "F2"])
        XCTAssertTrue(visibleWatchers([]).isEmpty)
    }

    func testSameFriendCanAppearTwice() {
        let now = Date()
        let shown = visibleWatchers([
            ProfileWatcher(name: "Ankit", openedAt: now),
            ProfileWatcher(name: "Ankit", openedAt: now.addingTimeInterval(-120)),
        ])
        XCTAssertEqual(shown.count, 2)
    }

    func testCardScaleMatchesAndroid() {
        XCTAssertEqual(watchersCardScale(pressed: false, held: false), 1)
        XCTAssertEqual(watchersCardScale(pressed: true, held: false), 0.96)
        XCTAssertEqual(watchersCardScale(pressed: true, held: true), 1.04)
        XCTAssertEqual(watchersCardScale(pressed: false, held: true), 1.04)
    }

    func testViewsNoticeShowsOnlyOnce() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        XCTAssertTrue(ViewsNoticeGate.consume(defaults: defaults))
        XCTAssertFalse(ViewsNoticeGate.consume(defaults: defaults))
        XCTAssertFalse(ViewsNoticeGate.consume(defaults: defaults))
    }
}

// MARK: - Back-fill of missed days (B12)

@MainActor
final class BackfillTests: XCTestCase {
    private let calendar = Calendar.current
    private var todayStart: Date { calendar.startOfDay(for: Date()) }
    private func dayStart(_ back: Int) -> Date { calendar.date(byAdding: .day, value: -back, to: todayStart)! }
    private func key(_ back: Int) -> String { DateUtil.localDay(dayStart(back)) }

    func testFreshInstallOnlyYesterday() {
        let days = StepTracker.backfillDays(lastDone: nil, todayStart: todayStart, calendar: calendar)
        XCTAssertEqual(days, [dayStart(1)])
    }

    func testUpToDateNothingToDo() {
        XCTAssertTrue(StepTracker.backfillDays(lastDone: key(1), todayStart: todayStart, calendar: calendar).isEmpty)
    }

    func testAppClosedForThreeDays() {
        // Aakancha: last finished day was 3 days ago → send day-2 and day-1, oldest first
        let days = StepTracker.backfillDays(lastDone: key(3), todayStart: todayStart, calendar: calendar)
        XCTAssertEqual(days, [dayStart(2), dayStart(1)])
    }

    func testNeverMoreThanCoreMotionKeeps() {
        let days = StepTracker.backfillDays(lastDone: key(30), todayStart: todayStart, calendar: calendar)
        XCTAssertEqual(days.count, StepTracker.maxBackfillDays)
        XCTAssertEqual(days.first, dayStart(StepTracker.maxBackfillDays))
        XCTAssertEqual(days.last, dayStart(1))
    }

    func testClockMovedBackwardsSendsNothing() {
        XCTAssertTrue(StepTracker.backfillDays(lastDone: DateUtil.localDay(), todayStart: todayStart, calendar: calendar).isEmpty)
        let tomorrow = DateUtil.localDay(calendar.date(byAdding: .day, value: 1, to: todayStart)!)
        XCTAssertTrue(StepTracker.backfillDays(lastDone: tomorrow, todayStart: todayStart, calendar: calendar).isEmpty)
    }
}

// MARK: - Friend status shown on Home and the friend screen

@MainActor
final class PeerStatusTests: XCTestCase {
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func activity(unlockedAgo: TimeInterval?, locked: Bool, online: Bool, seenAgo: TimeInterval? = nil) -> ActivityResponse {
        ActivityResponse(
            userId: "u",
            unlockedAt: unlockedAgo.map { iso(Date().addingTimeInterval(-$0)) },
            isLocked: locked,
            isOnline: online,
            lastSeenAt: seenAgo.map { iso(Date().addingTimeInterval(-$0)) }
        )
    }

    private func status(_ a: ActivityResponse?, stepsDate: String? = nil, steps: Int = 0) -> PeerStatus {
        let s = stepsDate.map {
            PeerStepsResponse(userId: "u", userName: "U", date: $0, stepCount: steps, updatedAt: nil, isActive: false, lastActiveAt: nil)
        }
        return PeerStatus(snapshot: PeerSnapshot(steps: s, activity: a, notSharing: false, fetchedAt: Date()))
    }

    func testNeverUnlockedIsNotShownAsLocked() {
        XCTAssertEqual(status(activity(unlockedAgo: nil, locked: true, online: false)).lock, .unknown)
        XCTAssertEqual(status(nil).lock, .unknown)
    }

    func testLockStates() {
        XCTAssertEqual(status(activity(unlockedAgo: 60, locked: true, online: true)).lock, .locked)
        XCTAssertEqual(status(activity(unlockedAgo: 60, locked: false, online: true)).lock, .unlocked)
        // Aakancha's case: unlocked long ago, phone silent since → not "Unlocked" as if live
        XCTAssertEqual(status(activity(unlockedAgo: 34 * 3600, locked: false, online: false)).lock, .offline)
    }

    func testFreshnessUsesServerLastSeen() {
        XCTAssertEqual(status(activity(unlockedAgo: 60, locked: true, online: true)).freshness(), .live)
        XCTAssertEqual(status(activity(unlockedAgo: 3600, locked: true, online: false, seenAgo: 10 * 60)).freshness(), .recent)
        XCTAssertEqual(status(activity(unlockedAgo: 3600, locked: true, online: false, seenAgo: 2 * 3600)).freshness(), .stale)
        XCTAssertEqual(
            status(activity(unlockedAgo: 3600, locked: true, online: false, seenAgo: 40 * 60)).updatedText(),
            "updated 40 min ago"
        )
    }

    func testYesterdaysStepsCountAsZeroToday() {
        let yesterday = DateUtil.localDay(Date().addingTimeInterval(-86400))
        XCTAssertEqual(status(nil, stepsDate: yesterday, steps: 9000).todaySteps, 0)
        XCTAssertEqual(status(nil, stepsDate: DateUtil.localDay(), steps: 1234).todaySteps, 1234)
    }
}

// MARK: - Dates

@MainActor
final class DateUtilTests: XCTestCase {
    func testParsesServerTimesWithAndWithoutMilliseconds() {
        XCTAssertNotNil(DateUtil.parseISO("2026-10-29T06:09:12.401Z"))
        XCTAssertNotNil(DateUtil.parseISO("2026-10-29T06:09:12Z"))
        XCTAssertNil(DateUtil.parseISO("yesterday"))
        XCTAssertNil(DateUtil.parseISO(""))
        XCTAssertNil(DateUtil.parseISO(nil))
    }

    func testShortRelativeBoundaries() {
        let now = Date()
        XCTAssertEqual(DateUtil.shortRelative(now.addingTimeInterval(-59), now: now), "just now")
        XCTAssertEqual(DateUtil.shortRelative(now.addingTimeInterval(-60), now: now), "1m ago")
        XCTAssertEqual(DateUtil.shortRelative(now.addingTimeInterval(-3599), now: now), "59m ago")
        XCTAssertEqual(DateUtil.shortRelative(now.addingTimeInterval(-3600), now: now), "1h ago")
        XCTAssertEqual(DateUtil.shortRelative(now.addingTimeInterval(-86400), now: now), "1d ago")
        // a time in the future (friend's clock ahead) never shows a negative age
        XCTAssertEqual(DateUtil.shortRelative(now.addingTimeInterval(600), now: now), "just now")
        XCTAssertNil(DateUtil.shortRelative(nil, now: now))
    }

    func testLocalDayFormat() {
        XCTAssertNotNil(DateUtil.localDay().range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression))
    }
}

// MARK: - Session storage (B8) and push environment (B2)

@MainActor
final class KeychainAndPushTests: XCTestCase {
    func testKeychainReadResult() {
        let key = "test-\(UUID().uuidString)"
        XCTAssertEqual(KeychainStore.readResult(key), .notFound)
        KeychainStore.save("abc", for: key)
        XCTAssertEqual(KeychainStore.readResult(key), .value("abc"))
        KeychainStore.save("def", for: key)   // update in place
        XCTAssertEqual(KeychainStore.read(key), "def")
        KeychainStore.delete(key)
        XCTAssertEqual(KeychainStore.readResult(key), .notFound)
    }

    func testApnsEnvironmentFromProfile() {
        let dev = """
        <dict>
            <key>aps-environment</key>
            <string>development</string>
        </dict>
        """
        let prod = "<key>aps-environment</key>\n\t<string>production</string>"
        XCTAssertEqual(AppDelegate.apnsEnvironment(fromProvisioningProfile: dev), "sandbox")
        XCTAssertEqual(AppDelegate.apnsEnvironment(fromProvisioningProfile: prod), "production")
        XCTAssertEqual(AppDelegate.apnsEnvironment(fromProvisioningProfile: "garbage"), "production")
    }

    func testSimulatorUsesSandbox() {
        #if targetEnvironment(simulator)
        XCTAssertEqual(AppDelegate.apnsEnvironment, "sandbox")
        #endif
    }

    func testBackgroundConfigIsInTheBuiltApp() {
        // Catches B1 coming back: these keys must be in the merged Info.plist.
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        XCTAssertEqual(ids, [AppDelegate.refreshTaskID])
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        XCTAssertTrue(modes.contains("fetch"))
        XCTAssertTrue(modes.contains("remote-notification"))
    }
}
