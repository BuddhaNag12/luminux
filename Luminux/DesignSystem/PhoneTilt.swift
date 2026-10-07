import CoreMotion
import SwiftUI

/// How far the phone has tilted from the way it's being held, smoothed, for a subtle depth effect.
@Observable
final class PhoneTilt {
    /// About −1…1 on each axis; zero at rest.
    private(set) var value: CGSize = .zero

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var rest: CMAcceleration?

    /// Gravity change (in g) that counts as a full tilt.
    private static let fullTilt = 0.3
    /// How quickly the effect follows the phone, and how quickly a new way of holding it becomes the centre.
    private static let follow = 0.18
    private static let recentre = 0.01

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }
            MainActor.assumeIsolated { self?.update(gravity) }
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        rest = nil
        withAnimation(MetroMotion.standard) { value = .zero }
    }

    private func update(_ gravity: CMAcceleration) {
        let previous = rest ?? gravity
        let rest = CMAcceleration(
            x: previous.x + (gravity.x - previous.x) * Self.recentre,
            y: previous.y + (gravity.y - previous.y) * Self.recentre,
            z: previous.z + (gravity.z - previous.z) * Self.recentre
        )
        self.rest = rest
        let target = CGSize(
            width: min(max((gravity.x - rest.x) / Self.fullTilt, -1), 1),
            height: min(max((gravity.y - rest.y) / Self.fullTilt, -1), 1)
        )
        let next = CGSize(
            width: value.width + (target.width - value.width) * Self.follow,
            height: value.height + (target.height - value.height) * Self.follow
        )
        // Skip changes too small to see, so a phone lying still doesn't redraw every frame.
        guard abs(next.width - value.width) > 0.002 || abs(next.height - value.height) > 0.002 else { return }
        value = next
    }
}

extension View {
    /// Shifts this view up to `distance` points as the phone tilts; a negative distance moves against the tilt, so
    /// things at different depths drift apart.
    func tiltParallax(_ distance: CGFloat) -> some View {
        modifier(TiltParallax(distance: distance))
    }
}

private struct TiltParallax: ViewModifier {
    let distance: CGFloat
    @Environment(PhoneTilt.self) private var tilt: PhoneTilt?

    func body(content: Content) -> some View {
        let value = tilt?.value ?? .zero
        content.offset(x: value.width * distance, y: -value.height * distance)
    }
}
