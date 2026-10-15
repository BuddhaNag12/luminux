import SwiftUI

/// Plays once on a cold launch, over the first screen: the sun flap mark assembles (the bottom half rises, the flap
/// falls onto its hinge, the sun lights, the hills draw), then the mark turns away on its left edge like a page leaving
/// and the screen fades into the app. It starts on black, like the static launch screen, so the hand-over doesn't
/// flash. About a second; Reduce Motion gets a short fade instead.
struct LaunchSplash: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = LogoMark.Phase.hidden
    @State private var isLeaving = false

    var body: some View {
        ZStack {
            Color.black.opacity(isLeaving ? 0 : 1)
            LogoMark(unit: 2.1, phase: reduceMotion ? .finished : phase, cutout: .black)
                .perspectiveRotation(isLeaving && !reduceMotion ? 70 : 0, axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.7)
                .opacity(isLeaving ? 0 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(!isLeaving)
        .accessibilityHidden(true)
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeOut(duration: 0.25)) { isLeaving = true } completion: { onFinish() }
            return
        }
        await LogoMark.playEntrance($phase)
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.easeIn(duration: 0.3)) { isLeaving = true } completion: { onFinish() }
    }
}
