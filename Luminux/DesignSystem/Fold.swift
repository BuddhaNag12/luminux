import SwiftUI

/// iPhone Duo's hinge, for effects only; layout follows size classes and the fold line instead. Stays flat on every
/// other iPhone.
@Observable
final class Hinge {
    /// 0 flat (or no hinge), 1 closed.
    private(set) var fold: CGFloat = 0
    /// Held part-way open, like a book or a tent.
    private(set) var isPartiallyOpen = false

    @available(iOS 27.1, *)
    func update(_ context: DeviceHingeContext) {
        guard let hinge = context.hinge else {
            fold = 0
            isPartiallyOpen = false
            return
        }
        fold = min(max(1 - hinge.angle.degrees / 180, 0), 1)
        isPartiallyOpen = hinge.status == .partiallyOpen
    }
}

extension EnvironmentValues {
    /// How far iPhone Duo's fold runs from the screen's left edge when it crosses the screen top to bottom; nil on
    /// other iPhones, and while the fold lies across the screen instead.
    @Entry var foldX: CGFloat?
    /// How far the fold runs from the screen's top when it lies across the screen (the open phone turned sideways, or
    /// stood up like a tent); nil otherwise.
    @Entry var foldY: CGFloat?
}

extension View {
    /// Reads the fold line and follows the hinge, for everything inside.
    func foldAware(_ hinge: Hinge) -> some View {
        modifier(FoldReader(hinge: hinge))
    }
}

private struct FoldReader: ViewModifier {
    let hinge: Hinge
    @State private var fold: CGRect?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .environment(\.foldX, fold.flatMap { $0.height > $0.width ? $0.midX : nil })
                .environment(\.foldY, fold.flatMap { $0.height > $0.width ? nil : $0.midY })
                .environment(hinge)
                .onGeometryChange(for: CGRect?.self) { proxy in
                    // Inactive too, so layout doesn't flip-flop as the phone opens and closes.
                    guard let fold = proxy.reservedRegions(kind: .division, options: .includeInactive).first else { return nil }
                    let origin = proxy.frame(in: .global).origin
                    return fold.frame.offsetBy(dx: origin.x, dy: origin.y)
                } action: { fold = $0 }
                .onHingeChange { _, context in hinge.update(context) }
        } else {
            content.environment(hinge)
        }
    }
}
