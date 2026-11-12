//
//  WhosWatching.swift
//  Consnow
//
//  "Seen by": who opened your profile today. Port of Android's WhosWatching.kt +
//  WatchersMapper.kt, same look and behaviour:
//   - hold the steps card for 0.6 s → card pops out, haptic, popup slides in from the left
//   - popup: eye header, divider, up to 3 newest viewers (first name + "5m ago")
//   - lift the finger (or start scrolling) → popup slides out
//   - small static eye on the steps card hints that it can be held
//

import SwiftUI
import UIKit

// MARK: - Model

/// A friend who opened your profile, and when.
struct ProfileWatcher: Equatable {
    let name: String
    let openedAt: Date
}

enum WatchersConfig {
    static let maxShown = 3
    static let holdDuration: TimeInterval = 0.6
}

/// "Sangita Pandey" -> "Sangita". Only the first word of a name is shown.
func watcherFirstName(_ full: String) -> String {
    full.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
}

/// The list shown in the popup: newest first, never more than 3.
func visibleWatchers(_ all: [ProfileWatcher]) -> [ProfileWatcher] {
    Array(all.sorted { $0.openedAt > $1.openedAt }.prefix(WatchersConfig.maxShown))
}

/// Card size: pops in while pressed, pops out while the list is showing.
func watchersCardScale(pressed: Bool, held: Bool) -> CGFloat {
    if held { return 1.04 }
    if pressed { return 0.96 }
    return 1
}

// MARK: - API

enum WatchersAPI {
    /// Loads today's viewers (GET /profile-views?since=<00:00 today>).
    /// nil when offline or the server failed, so the caller keeps what it had.
    static func fetchToday() async -> [ProfileWatcher]? {
        let formatter = ISO8601DateFormatter()
        let since = formatter.string(from: Calendar.current.startOfDay(for: Date()))
        do {
            let rows = try await APIClient.shared.send(
                "GET", "profile-views",
                query: [URLQueryItem(name: "since", value: since)],
                as: [ProfileViewResponse].self
            )
            // A row with an unreadable time is skipped.
            return rows.compactMap { row in
                DateUtil.parseISO(row.viewedAt).map { ProfileWatcher(name: row.name, openedAt: $0) }
            }
        } catch {
            return nil
        }
    }

    /// POST /profile-views/:ownerId when a friend's profile is opened
    /// (the server ignores repeats within 5 min). Errors are ignored.
    static func recordView(of ownerId: String) async {
        _ = try? await APIClient.shared.sendRaw("POST", "profile-views/\(ownerId)")
    }
}

// MARK: - Colours (Android dark theme values)

enum WatchersPalette {
    static let accent = Color(red: 0x2D / 255, green: 0xD4 / 255, blue: 0xBF / 255)          // #2DD4BF
    static let surface = Color(red: 0x1E / 255, green: 0x29 / 255, blue: 0x3B / 255)         // #1E293B
    static let surfaceVariant = Color(red: 0x33 / 255, green: 0x41 / 255, blue: 0x55 / 255)  // #334155
    static let outlineVariant = Color(red: 0x49 / 255, green: 0x45 / 255, blue: 0x4F / 255)  // #49454F
    static let secondaryContainer = Color(red: 0x4A / 255, green: 0x44 / 255, blue: 0x58 / 255) // #4A4458
    static let onSurface = Color(red: 0xF1 / 255, green: 0xF5 / 255, blue: 0xF9 / 255)       // #F1F5F9
    static let onSurfaceVariant = Color(red: 0xCA / 255, green: 0xC4 / 255, blue: 0xD0 / 255) // #CAC4D0
}

enum WatchersMotion {
    /// FastOutSlowIn, 260 ms in / 180 ms out (same as Android).
    static let enter = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.26)
    static let exit = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.18)
    /// Springy card scale (Android: DampingRatioMediumBouncy, StiffnessMedium).
    static let cardSpring = Animation.interpolatingSpring(stiffness: 1500, damping: 38.7)

    /// Slides in from / out to the left, growing from its top-left corner.
    static func popupTransition(width: CGFloat) -> AnyTransition {
        let move = AnyTransition.offset(x: -width / 2)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.82, anchor: .topLeading))
        return .asymmetric(insertion: move, removal: move)
    }

    /// Android: LongPress haptic + a 40 ms buzz.
    static func holdHaptic() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}

// MARK: - Popup

struct WhosWatchingPopup: View {
    let watchers: [ProfileWatcher]
    /// Half the screen width, like Android.
    let width: CGFloat

    var body: some View {
        let rows = visibleWatchers(watchers)
        VStack(alignment: .leading, spacing: 8) {
            // Header is just the eye icon (no heading text)
            ZStack {
                Circle().fill(WatchersPalette.accent.opacity(0.16))
                EyeIcon(color: WatchersPalette.accent)
                    .frame(width: 18, height: 18)
            }
            .frame(width: 30, height: 30)

            Rectangle()
                .fill(WatchersPalette.outlineVariant)
                .frame(height: 1)

            if rows.isEmpty {
                Text("No one has looked at your profile yet today.")
                    .font(.system(size: 14))
                    .foregroundStyle(WatchersPalette.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, watcher in
                    WatcherRow(watcher: watcher)
                }
            }
        }
        .padding(16)
        .frame(width: max(width, 160), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(WatchersPalette.surface)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WatchersPalette.outlineVariant, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct WatcherRow: View {
    let watcher: ProfileWatcher

    var body: some View {
        let name = watcherFirstName(watcher.name)
        HStack(spacing: 0) {
            ZStack {
                Circle().fill(WatchersPalette.secondaryContainer)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WatchersPalette.onSurface)
            }
            .frame(width: 30, height: 30)

            Spacer().frame(width: 10)

            // Name on top, time under it: the name gets the whole row width
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WatchersPalette.onSurface)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(DateUtil.shortRelative(watcher.openedAt) ?? "Unknown")
                    .font(.system(size: 12))
                    .foregroundStyle(WatchersPalette.onSurfaceVariant)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 44)
    }
}

// MARK: - Eye

/// Small static eye on the steps card: tells people the card can be held to see who viewed you.
struct WatchersHintBadge: View {
    var body: some View {
        EyeIcon(color: WatchersPalette.accent.opacity(0.45))
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

struct EyeIcon: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            EyeShape()
                .stroke(color, style: StrokeStyle(lineWidth: geo.size.width * 0.09, lineCap: .round))
        }
    }
}

/// Same outline as Android's EyeIcon canvas: almond + pupil ring.
private struct EyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }

        var path = Path()
        path.move(to: pt(0.08, 0.5))
        path.addQuadCurve(to: pt(0.92, 0.5), control: pt(0.5, 0.02))
        path.addQuadCurve(to: pt(0.08, 0.5), control: pt(0.5, 0.98))
        path.closeSubpath()
        let r = w * 0.15
        let c = pt(0.5, 0.5)
        path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        return path
    }
}

// MARK: - Hold gesture

/// Port of Android's Modifier.onHoldFor: calls `onHold` once the finger has stayed down
/// for 0.6 s, then `onRelease` when it lifts (or the finger moves, e.g. the user scrolls).
/// Never blocks scrolling or pull-to-refresh.
struct HoldGestureView: UIViewRepresentable {
    var holdDuration: TimeInterval = WatchersConfig.holdDuration
    var onPressChange: (Bool) -> Void
    var onHold: () -> Void
    var onRelease: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        recognizer.minimumPressDuration = 0       // track from the first touch
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HoldGestureView
        private var start: CGPoint = .zero
        private var holdTask: Task<Void, Never>?
        private var active = false
        private var held = false

        /// More movement than this before/while holding = scrolling, not holding.
        private let slop: CGFloat = 10

        init(parent: HoldGestureView) {
            self.parent = parent
        }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                // Window coordinates, so a scrolling list still counts as movement.
                start = recognizer.location(in: nil)
                active = true
                held = false
                parent.onPressChange(true)
                let delay = parent.holdDuration
                holdTask?.cancel()
                holdTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.fireHold()
                }
            case .changed:
                guard active else { return }
                let p = recognizer.location(in: nil)
                if hypot(p.x - start.x, p.y - start.y) > slop { finish() }
            case .ended, .cancelled, .failed:
                finish()
            default:
                break
            }
        }

        private func fireHold() {
            guard active, !held else { return }
            held = true
            parent.onHold()
        }

        private func finish() {
            guard active else { return }
            active = false
            holdTask?.cancel()
            holdTask = nil
            if held {
                held = false
                parent.onRelease()
            }
            parent.onPressChange(false)
        }

        // Let the ScrollView (and pull-to-refresh) work at the same time.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
