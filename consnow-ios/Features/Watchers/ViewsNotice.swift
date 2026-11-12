//
//  ViewsNotice.swift
//  Consnow
//
//  Port of Android's ViewsNotice.kt: a short, one-time heads-up on the Connect screen
//  that friends can see when you open their profile. Shows once (6 s), then never again.
//

import SwiftUI

/// Lets the notice through exactly once, ever.
enum ViewsNoticeGate {
    private static let key = "views_notice_seen"

    static func consume(defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: key) { return false }
        defaults.set(true, forKey: key)
        return true
    }
}

struct ViewsNotice: View {
    static let visibleFor: Duration = .seconds(6)

    @State private var visible = false

    var body: some View {
        ZStack {
            // Keeps the view on screen (so .task runs) even while the notice is hidden.
            Color.clear.frame(width: 1, height: 1)
            if visible {
                Text("Heads up: friends you connect with can see when you open their profile.")
                    .font(.system(size: 12))
                    .foregroundStyle(WatchersPalette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(WatchersPalette.surfaceVariant)
                    )
                    .transition(.opacity.combined(with: .offset(y: -20)))
            }
        }
        .task {
            guard ViewsNoticeGate.consume() else { return }
            withAnimation { visible = true }
            try? await Task.sleep(for: Self.visibleFor)
            withAnimation { visible = false }
        }
    }
}
