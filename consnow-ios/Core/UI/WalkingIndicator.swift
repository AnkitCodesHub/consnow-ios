//
//  WalkingIndicator.swift
//  Consnow
//
//  An animated person walking in place: knees bend, arms swing, the body
//  bounces slightly and the ground slides under the feet. Far-side arm and
//  leg are drawn fainter for depth. Same design as the Android app.
//
//  Drop-in replacement for a plain "Walking now" label:
//
//      if status.isWalking { WalkingNowChip() }
//

import SwiftUI

/// "Walking now" pill: animated walker + label.
struct WalkingNowChip: View {
    var label: String = "Walking now"

    var body: some View {
        HStack(spacing: 6) {
            WalkingFigure()
                .frame(width: 34, height: 34)
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accent)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.accent.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// The walking person on its own (any size; it scales to its frame height).
struct WalkingFigure: View {
    var color: Color = .accent
    var showGround = true
    /// Seconds for one full stride (both legs).
    var stride: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion
                ? 0.25
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: stride) / stride
            Canvas { ctx, size in
                WalkerDrawing(t: t, color: color, showGround: showGround).draw(in: &ctx, size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One frame of the walk cycle on a 100 × 112 design grid.
private struct WalkerDrawing {
    let t: Double
    let color: Color
    let showGround: Bool

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let s = size.height / 112
        let ox = size.width / 2 - 50 * s
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: y * s) }

        let w = 2 * Double.pi * t
        let bob = -3 * (cos(2 * w) + 1) / 2
        let hip = (50.0, 56 + bob)
        let shoulder = (51.5, 31 + bob)

        func leg(_ ph: Double) -> [(Double, Double)] {
            let a = w + ph
            let thigh = 0.46 * sin(a)
            let knee = 0.12 + 0.95 * pow(max(0, cos(a)), 1.6)
            let k = (hip.0 + 22 * sin(thigh), hip.1 + 22 * cos(thigh))
            let shin = thigh - knee
            let foot = (k.0 + 22 * sin(shin), k.1 + 22 * cos(shin))
            return [hip, k, foot]
        }

        func arm(_ ph: Double) -> [(Double, Double)] {
            let a = w + ph
            let upper = -0.5 * sin(a)
            let e = (shoulder.0 + 16 * sin(upper), shoulder.1 + 16 * cos(upper))
            let fore = upper + 0.55 + 0.25 * max(0, -sin(a))
            let hand = (e.0 + 14 * sin(fore), e.1 + 14 * cos(fore))
            return [shoulder, e, hand]
        }

        func limb(_ points: [(Double, Double)], _ alpha: Double, _ width: Double) {
            var path = Path()
            for (i, pt) in points.enumerated() {
                if i == 0 { path.move(to: p(pt.0, pt.1)) } else { path.addLine(to: p(pt.0, pt.1)) }
            }
            ctx.stroke(path, with: .color(color.opacity(alpha)),
                       style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
        }

        if showGround {
            let offset = (t * 24).truncatingRemainder(dividingBy: 12)
            var x = -12.0
            while x < 112 {
                let xx = x - offset
                if xx >= 4 && xx <= 92 {
                    let fade = 1 - abs(xx - 50) / 48
                    let origin = p(xx, 103)
                    ctx.fill(Path(CGRect(x: origin.x, y: origin.y, width: 6 * s, height: 2.2 * s)),
                             with: .color(color.opacity(0.45 * fade)))
                }
                x += 12
            }
        }

        // Far side first (fainter), then body, near side on top.
        limb(arm(.pi), 0.45, 7)
        limb(leg(.pi), 0.45, 8)
        limb([hip, shoulder], 1, 9)
        limb(leg(0), 1, 8)
        let head = p(53, 17 + bob)
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 9 * s, y: head.y - 9 * s, width: 18 * s, height: 18 * s)),
                 with: .color(color))
        limb(arm(0), 1, 7)
    }
}

#Preview("Walking") {
    VStack(spacing: 28) {
        WalkingFigure().frame(width: 160, height: 110)
        WalkingNowChip()
        HStack(spacing: 8) {
            WalkingFigure(showGround: false).frame(width: 24, height: 24)
            Text("Aditya · walking").foregroundStyle(.white)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.background)
}
