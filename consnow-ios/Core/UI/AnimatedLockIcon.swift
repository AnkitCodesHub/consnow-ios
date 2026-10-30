//
//  AnimatedLockIcon.swift
//  Consnow
//
//  The big lock on the friend screen. Flat, solid padlock:
//  white when locked, accent teal when unlocked, dark keyhole.
//   • Unlock: keyhole turns like a key, shackle pops up and turns around its
//     right leg in 3D (like a real padlock),
//     color fades white → accent, a soft ring pulses out, light haptic.
//   • Lock:   shackle drops back in, body "thunks", ring pulses, firmer haptic.
//   • While unlocked with live data, the glow gently breathes.
//   • Reduce Motion: simple fade, no bounce or ring.
//

import SwiftUI

struct AnimatedLockIcon: View {
    let isUnlocked: Bool
    /// Fresh data: enables the breathing glow.
    var isLive: Bool = false
    /// Dim the lock when the data is old.
    var isStale: Bool = false
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 = shackle seated, 1 = popped up
    @State private var lift: CGFloat
    /// 0 = closed side, 1 = turned 180° around its right leg (like a real padlock)
    @State private var spin: CGFloat
    /// 0 = keyhole upright, 1 = turned like a key
    @State private var keyTurn: CGFloat
    @State private var ringProgress: CGFloat = 1   // 1 = finished / invisible
    @State private var breathe = false

    init(isUnlocked: Bool, isLive: Bool = false, isStale: Bool = false, size: CGFloat = 96) {
        self.isUnlocked = isUnlocked
        self.isLive = isLive
        self.isStale = isStale
        self.size = size
        let start: CGFloat = isUnlocked ? 1 : 0   // no animation on first appearance
        _lift = State(initialValue: start)
        _spin = State(initialValue: start)
        _keyTurn = State(initialValue: start)
    }

    private var tint: Color { isUnlocked ? .accent : Color(red: 0.93, green: 0.95, blue: 0.97) }
    /// 1 design unit = size / 100 (same grid as the design preview).
    private var u: CGFloat { size / 100 }

    var body: some View {
        ZStack {
            // Soft halo (breathes while unlocked and live)
            Circle()
                .fill(tint.opacity(isUnlocked ? (breathe ? 0.24 : 0.12) : 0.07))
                .frame(width: 124 * u, height: 124 * u)
                .offset(y: 10 * u)

            // Ring pulse on every change
            Circle()
                .stroke(tint, lineWidth: 2)
                .frame(width: 80 * u, height: 80 * u)
                .scaleEffect(1 + 0.8 * ringProgress)
                .opacity(Double(1 - ringProgress) * 0.7)
                .offset(y: 10 * u)

            glyph
        }
        .frame(width: size * 1.4, height: size * 1.3)
        .saturation(isStale ? 0.4 : 1)
        .opacity(isStale ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.4), value: isUnlocked)
        .animation(.easeInOut(duration: 0.3), value: isStale)
        .sensoryFeedback(trigger: isUnlocked) { _, unlocked in
            unlocked ? SensoryFeedback.impact(weight: .light) : SensoryFeedback.impact(weight: .medium)
        }
        .onChange(of: isUnlocked) { _, unlocked in animateChange(to: unlocked) }
        .onChange(of: isLive) { _, _ in updateBreathing() }
        .onAppear { updateBreathing() }
        .accessibilityElement()
        .accessibilityLabel(isUnlocked ? "Phone unlocked" : "Phone locked")
    }

    // MARK: - Glyph (100 × 100 design grid)

    private var glyph: some View {
        ZStack {
            // Shackle: thick rounded stroke, legs tucked behind the body.
            // Unlock: pops up, then turns around its right leg in 3D, like a real padlock.
            ShackleShape()
                .stroke(tint, style: StrokeStyle(lineWidth: 8.5 * u, lineCap: .round))
                .frame(width: 38 * u, height: 41 * u)
                .rotation3DEffect(
                    .degrees(180 * spin),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .trailing,
                    perspective: 0.45
                )
                .offset(y: -14 * u * lift)
                .position(x: 50 * u, y: 35.5 * u)

            // Solid body
            RoundedRectangle(cornerRadius: 13 * u, style: .continuous)
                .fill(tint)
                .frame(width: 64 * u, height: 44 * u)
                .scaleEffect(x: squash.width, y: squash.height, anchor: .bottom)
                .position(x: 50 * u, y: 72 * u)

            // Dark keyhole, turns like a key when unlocking
            Keyhole(unit: u)
                .rotationEffect(.degrees(-90 * keyTurn))
                .position(x: 50 * u, y: 72 * u)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Animation

    @State private var squash = CGSize(width: 1, height: 1)
    @State private var sequence: Task<Void, Never>?

    private func animateChange(to unlocked: Bool) {
        let target: CGFloat = unlocked ? 1 : 0
        sequence?.cancel()   // a quick second change wins over a half-finished one
        squash = CGSize(width: 1, height: 1)
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.3)) {
                lift = target; spin = target; keyTurn = target
            }
            updateBreathing()
            return
        }

        if unlocked {
            // 1. key turns  2. shackle pops up  3. shackle turns around its right leg
            withAnimation(.easeOut(duration: 0.2)) { keyTurn = 1 }
            sequence = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { lift = 1 }
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { spin = 1 }
            }
        } else {
            // 1. shackle turns back  2. drops into the body  3. body "thunks", key turns back
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { spin = 0 }
            sequence = Task {
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { lift = 0 }
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.14, dampingFraction: 0.5)) {
                    squash = CGSize(width: 1.05, height: 0.88)
                }
                withAnimation(.easeOut(duration: 0.2)) { keyTurn = 0 }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                    squash = CGSize(width: 1, height: 1)
                }
            }
        }

        ringProgress = 0
        withAnimation(.easeOut(duration: 0.9)) { ringProgress = 1 }

        updateBreathing()
    }

    private func updateBreathing() {
        if isUnlocked && isLive && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        } else {
            withAnimation(.easeOut(duration: 0.4)) { breathe = false }
        }
    }
}

/// Upside-down "U": the legs end at the bottom of the frame.
private struct ShackleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct Keyhole: View {
    let unit: CGFloat
    var body: some View {
        ZStack(alignment: .top) {
            Circle()
                .frame(width: 12 * unit, height: 12 * unit)
            Capsule()
                .frame(width: 4.6 * unit, height: 11 * unit)
                .offset(y: 8 * unit)
        }
        .frame(width: 12 * unit, height: 19 * unit, alignment: .top)
        .foregroundStyle(Color.background)
        .offset(y: 2 * unit)
    }
}

#Preview("Lock / unlock") {
    struct Demo: View {
        @State private var unlocked = false
        var body: some View {
            VStack(spacing: 28) {
                AnimatedLockIcon(isUnlocked: unlocked, isLive: true, size: 110)
                Button(unlocked ? "Lock" : "Unlock") { unlocked.toggle() }
                    .buttonStyle(.borderedProminent)
                    .tint(.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.background)
        }
    }
    return Demo()
}
