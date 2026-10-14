import SwiftUI

/// Plays once on a cold launch, over the first screen: the app icon's three tiles stack in one after another, the
/// photo's sun and hills appear on the front tile, then the stack lifts away. It starts on black, like the static
/// launch screen, so the hand-over doesn't flash. About a second; Reduce Motion gets a short fade instead.
struct LaunchSplash: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilesIn = [false, false, false]
    @State private var showsPhoto = false
    @State private var isLeaving = false

    var body: some View {
        ZStack {
            Color.black.opacity(isLeaving ? 0 : 1)
            LogoMark(
                unit: 2.1,
                tilesIn: reduceMotion ? [true, true, true] : tilesIn,
                showsPhoto: showsPhoto || reduceMotion,
                cutout: .black
            )
            .scaleEffect(isLeaving && !reduceMotion ? 1.6 : 1)
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
        await LogoMark.playEntrance(tilesIn: $tilesIn, showsPhoto: $showsPhoto)
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.easeIn(duration: 0.3)) { isLeaving = true } completion: { onFinish() }
    }
}
