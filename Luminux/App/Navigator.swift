import SwiftUI

enum Route: Hashable {
    case collection(page: Int, showsJumpList: Bool = false)
    case album(String)
    case settings
}

struct ViewerRequest: Identifiable, Hashable {
    let source: AssetSource
    let startID: String
    /// Position of `startID` in the source, so the pager opens on it at first layout.
    let startIndex: Int

    var id: String { startID }
}


@Observable
final class Navigator {
    var path: [Route] = []
    var viewer: ViewerRequest?
    /// The photo showing in the viewer, so the zoom closes onto the right tile.
    var viewerCurrentID: String?
    /// The top page's tiles are swinging out before `pop()` removes it.
    private(set) var isLeaving = false

    func push(_ route: Route) {
        withAnimation(MetroMotion.standard) { path.append(route) }
    }

    func pop() {
        guard !path.isEmpty, !isLeaving else { return }
        guard !UIAccessibility.isReduceMotionEnabled else {
            withAnimation(MetroMotion.standard) { _ = path.removeLast() }
            return
        }
        // Feather the page out first, then drop it without a second transition.
        isLeaving = true
        Task {
            try? await Task.sleep(for: .milliseconds(340))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                _ = path.removeLast()
                isLeaving = false
            }
        }
    }

    func openViewer(_ source: AssetSource, at assetID: String, index: Int) {
        viewerCurrentID = assetID
        viewer = ViewerRequest(source: source, startID: assetID, startIndex: index)
    }
}

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID?
}

extension View {
    /// Marks a tile as the place the viewer zooms out of and back into.
    @ViewBuilder
    func zoomSource(id: String) -> some View {
        modifier(ZoomSourceModifier(id: id))
    }
}

private struct ZoomSourceModifier: ViewModifier {
    let id: String
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Page stack with turnstile transitions and an interactive swipe from the left edge to go back.
struct MetroStack<Root: View, Destination: View>: View {
    @ViewBuilder var root: Root
    @ViewBuilder var destination: (Route) -> Destination

    @Environment(Navigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backProgress: CGFloat = 0
    @State private var width: CGFloat = 1

    var body: some View {
        ZStack {
            page(depth: 0) { root }
            ForEach(Array(navigator.path.enumerated()), id: \.offset) { index, route in
                page(depth: index + 1) { destination(route) }
                    .transition(.asymmetric(
                        // The page's own tiles feather in; the whole-page turn is only for finishing the back swipe.
                        insertion: .identity,
                        removal: .metroPage(.backward, reduceMotion: reduceMotion)
                    ))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .overlay(alignment: .leading) {
            if !navigator.path.isEmpty {
                Color.clear
                    .frame(width: 20)
                    .contentShape(Rectangle())
                    .gesture(backGesture)
                    .ignoresSafeArea()
            }
        }
    }

    private func page<Content: View>(depth: Int, @ViewBuilder content: () -> Content) -> some View {
        let top = navigator.path.count
        let isTop = depth == top
        let isUnder = depth == top - 1
        let isLeaving = isTop && navigator.isLeaving
        let isDragging = backProgress > 0
        let revealsUnder = isDragging || navigator.isLeaving

        // Pushes and pops feather each page's tiles; only the back swipe turns whole pages, following the finger.
        let pageAngle: Double = if reduceMotion || !isDragging {
            0
        } else if isTop {
            -80 * backProgress
        } else {
            Feather.coverAngle * (1 - backProgress)
        }
        let featherAngle: Double = if isLeaving {
            Feather.leaveAngle
        } else if isTop || (isUnder && revealsUnder) {
            0
        } else {
            Feather.coverAngle
        }
        let isCovered = !isTop && !(isUnder && revealsUnder)
        let opacity: Double = if isTop {
            isLeaving ? 0 : 1 - backProgress * 0.6
        } else if isUnder {
            navigator.isLeaving ? 1 : backProgress
        } else {
            0
        }

        return content()
            .featherScope(coveredAngle: featherAngle)
            .perspectiveRotation(pageAngle, axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.7)
            .opacity(opacity)
            // Leaving and covered pages keep their background until their tiles have swung away.
            .animation(isLeaving ? .easeIn(duration: 0.14).delay(0.16) : MetroMotion.standard, value: isLeaving)
            .animation(isCovered ? .easeIn(duration: 0.1).delay(0.2) : MetroMotion.standard, value: isCovered)
            .allowsHitTesting(isTop && !isLeaving)
            .accessibilityHidden(!isTop)
            .zIndex(Double(depth))
    }

    private var backGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                backProgress = min(max(value.translation.width / width, 0), 1)
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width / width
                if projected > 0.45 {
                    withAnimation(MetroMotion.standard) {
                        backProgress = 0
                        _ = navigator.path.removeLast()
                    }
                } else {
                    withAnimation(MetroMotion.release) { backProgress = 0 }
                }
            }
    }
}
