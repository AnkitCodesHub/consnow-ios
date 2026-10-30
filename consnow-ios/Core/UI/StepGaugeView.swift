//
//  StepGaugeView.swift
//  Consnow
//

import SwiftUI

struct StepGaugeView: View {
    let steps: Int
    var title: String? = nil
    var size: CGFloat = 220
    var goal: Int = 10_000
    var placeholder = false

    private var progress: Double { min(Double(steps) / Double(goal), 1.0) }
    private var ring: CGFloat { size * 0.75 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.cardBackground)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: ring, height: ring)
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.15, to: 0.15 + (0.70 * (placeholder ? 0 : progress)))
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: ring, height: ring)
                .rotationEffect(.degrees(90))
                .animation(.easeOut, value: progress)

            VStack(spacing: 2) {
                if let title {
                    Text(title)
                        .foregroundColor(.textSecondary)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Image(systemName: "figure.walk")
                    .font(.title2)
                    .foregroundColor(.accent)
                Text(placeholder ? "---" : steps.formatted())
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeOut, value: steps)
                if !placeholder {
                    Text(PeerStatus.distance(for: steps))
                        .foregroundColor(.textSecondary)
                        .font(.subheadline)
                }
            }
        }
    }
}
