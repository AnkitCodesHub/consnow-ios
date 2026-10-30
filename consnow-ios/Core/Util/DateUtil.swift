//
//  DateUtil.swift
//  Consnow
//

import Foundation

enum DateUtil {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Local calendar day as YYYY-MM-DD — the `date` the backend expects.
    static func localDay(_ date: Date = Date()) -> String {
        dayFormatter.timeZone = .current
        return dayFormatter.string(from: date)
    }

    /// Parses server timestamps with or without milliseconds
    /// ("2026-10-29T06:09:12.401Z" and "2026-10-29T06:09:12Z").
    static func parseISO(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return isoWithFraction.date(from: string) ?? isoPlain.date(from: string)
    }

    /// "just now", "5 minutes ago", "2 hours ago", "yesterday"...
    static func relative(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        if now.timeIntervalSince(date) < 60 { return "just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    /// Compact style used on the friend screen, same as Android: "just now", "3m ago", "2h ago", "1d ago".
    static func shortRelative(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = Int(max(0, now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }

    static func epochMillis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
