import SwiftUI

enum Route: Hashable {
    case collection(page: Int, showsJumpList: Bool = false)
    case album(String)
    case settings
    case pro
    case about
    case journal
    case journalEntry(String)
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
        // Let the page's items sink away first, then drop it without a second transition.
        isLeaving = true
        Task {
            try? await Task.sleep(for: .seconds(Feather.exitTime))
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

/// Page stack: pages' items rise in and out in staggered waves, and a swipe from the left edge slides the page away.
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
                    // Items animate themselves; pages only cross-fade with Reduce Motion.
                    .transition(reduceMotion ? .opacity : .identity)
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

        let itemState: FeatherState = if isLeaving {
            .below
        } else if isTop || (isUnder && revealsUnder) {
            .shown
        } else {
            .above
        }
        let isCovered = itemState == .above
        let opacity: Double = if isTop {
            isLeaving ? 0 : 1 - backProgress * 0.5
        } else if isUnder && revealsUnder {
            navigator.isLeaving ? 1 : backProgress
        } else {
            0
        }

        // Only offset and opacity change, so the hub's photo background keeps covering the safe areas.
        return content()
            .featherScope(itemState)
            .offset(x: isTop ? backProgress * width : 0)
            .opacity(opacity)
            // Leaving and covered pages keep their background until their items have moved away.
            .animation(isLeaving ? .easeIn(duration: 0.12).delay(Feather.exitTime - 0.12) : MetroMotion.standard, value: isLeaving)
            .animation(isCovered ? .easeIn(duration: 0.1).delay(Feather.coverFadeDelay) : MetroMotion.standard, value: isCovered)
            .allowsHitTesting(isTop && !isLeaving && !isDragging)
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
                    // Finish the slide, then drop the page without a second animation.
                    withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                        backProgress = 1
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            _ = navigator.path.removeLast()
                            backProgress = 0
                        }
                    }
                } else {
                    withAnimation(MetroMotion.release) { backProgress = 0 }
                }
            }
    }
}
