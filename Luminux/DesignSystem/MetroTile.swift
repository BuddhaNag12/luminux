import SwiftUI
import UIKit

/// Press feedback for tiles: pressing near an edge tips that edge away, pressing the centre pushes the tile in.
struct Tilt: Equatable {
    var angle: Double
    var axisX: CGFloat
    var axisY: CGFloat
    var scale: CGFloat

    static let rest = Tilt(angle: 0, axisX: 0, axisY: 0, scale: 1)

    static func pressed(at point: CGPoint?, in size: CGSize, maxAngle: Double = 12, depth: CGFloat = 0.04) -> Tilt {
        guard let point, size.width > 0, size.height > 0 else {
            return Tilt(angle: 0, axisX: 0, axisY: 0, scale: 1 - depth)
        }
        let dx = min(max((point.x - size.width / 2) / (size.width / 2), -1), 1)
        let dy = min(max((point.y - size.height / 2) / (size.height / 2), -1), 1)
        let reach = min(hypot(dx, dy), 1)
        // Big tiles tip less, so the far edge doesn't swing too far.
        let sizeFactor = min(1, 180 / max(size.width, size.height))
        return Tilt(
            angle: maxAngle * Double(reach * sizeFactor),
            axisX: -dy,
            axisY: dx,
            scale: 1 - depth * (1 - reach * 0.5)
        )
    }
}

/// A square-cornered tile that tilts toward the finger while pressed.
struct MetroTile<Content: View>: View {
    var title: String?
    let action: () -> Void
    @ViewBuilder var content: Content

    @State private var touch: CGPoint?
    @State private var size: CGSize = .zero

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if let title {
                        Text(title)
                            .font(.metroCaption)
                            .foregroundStyle(.white)
                            .padding(10)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(TiltButtonStyle(touch: touch, size: size))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .gesture(TouchLocationRecognizer { touch = $0 })
        .accessibilityLabel(title ?? "")
    }
}

struct TiltButtonStyle: ButtonStyle {
    var touch: CGPoint?
    var size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let tilt = configuration.isPressed && !reduceMotion ? Tilt.pressed(at: touch, in: size) : .rest
        configuration.label
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .scaleEffect(tilt.scale)
            .perspectiveRotation(tilt.angle, axis: (x: tilt.axisX, y: tilt.axisY, z: 0), perspective: 0.6)
            .animation(configuration.isPressed ? MetroMotion.press : MetroMotion.release, value: tilt)
    }
}

/// Reports where a finger is on the view without taking the touch from buttons or scroll views.
struct TouchLocationRecognizer: UIGestureRecognizerRepresentable {
    var onChange: (CGPoint?) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: onChange(context.converter.localLocation)
        default: onChange(nil)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
