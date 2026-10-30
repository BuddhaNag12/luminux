import SwiftUI

enum Route: Hashable {
    case collection(page: Int, showsJumpList: Bool = false)
    case album(String)
    case settings
    case pro
    case about
    case journal
    case journalEntry(String)
    case photoSet(String)
    case place(String)
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
    /// Stack depth of the page a tile sits on; hidden pages below keep the same photos as zoom sources.
    @Entry var zoomPageDepth = 0
}

/// Zoom source ID scoped to its page, so the viewer zooms into the visible tile, not a hidden page's copy.
func zoomSourceID(_ assetID: String, pageDepth: Int) -> String { "\(pageDepth)/\(assetID)" }

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
    @Environment(\.zoomPageDepth) private var pageDepth

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: zoomSourceID(id, pageDepth: pageDepth), in: namespace)
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
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLaunchSplashShowing) private var isSplashShowing
    @State private var backProgress: CGFloat = 0
    @State private var width: CGFloat = 1
    @State private var height: CGFloat = 1
    /// Pages deeper than this wait, hidden, for the page they opened from to scatter away first (zoom only).
    @State private var enteredDepth = 0
    @State private var topInset: CGFloat = 0

    /// Room above every page's first line. iPhone Duo open and sideways puts the status bar down the side, leaving no
    /// top inset, and the "LUMINUX" line sat against the screen's edge.
    private static var minimumTopInset: CGFloat { 20 }

    var body: some View {
        ZStack {
            page(depth: 0) { root }
            ForEach(Array(navigator.path.enumerated()), id: \.offset) { index, route in
                // A zooming page isn't built until the page it opened from has scattered away: building it (a photo
                // grid, say) while the tiles flew out dropped frames.
                if !zooms || index + 1 <= enteredDepth {
                    page(depth: index + 1) { destination(route) }
                        // Items animate themselves; with Reduce Motion pages only cross-fade.
                        .transition(reduceMotion ? .opacity : .identity)
                }
            }
        }
        .safeAreaPadding(.top, max(Self.minimumTopInset - topInset, 0))
        // Measured outside the padding, so it reads the screen's own inset.
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top.rounded() } action: { topInset = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = max($0, 1) }
        .environment(\.featherStyle, zooms ? .zoom : .turnstile)
        .onChange(of: navigator.path.count, initial: true) { old, count in
            guard zooms, count > old else { return enteredDepth = count }
            Task {
                try? await Task.sleep(for: .seconds(Self.zoomEntryDelay))
                withAnimation(Self.zoomAnimation) { enteredDepth = navigator.path.count }
            }
        }
        .environment(\.featherScreen, CGSize(width: width, height: height))
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

    private var zooms: Bool { settings.pageTransition == .zoom && !reduceMotion }

    /// A page opening grows from this, and one closing shrinks back to it.
    private static var zoomedIn: CGFloat { 0.9 }
    private static var zoomAnimation: Animation { .timingCurve(Feather.decelerate, duration: 0.4) }
    /// Like Windows 10 Mobile opening an app: the start screen's items fly out, then the app fades in, growing from
    /// slightly smaller. The covered page's items are mostly gone by now.
    private static var zoomEntryDelay: Double { 0.4 }

    private func page<Content: View>(depth: Int, @ViewBuilder content: () -> Content) -> some View {
        let top = navigator.path.count
        let isTop = depth == top
        let isUnder = depth == top - 1
        let isLeaving = isTop && navigator.isLeaving
        let isDragging = backProgress > 0
        let revealsUnder = isDragging || navigator.isLeaving

        let itemState: FeatherState = if isLeaving || (depth == 0 && isSplashShowing) {
            // The first page waits under the launch splash and opens as it goes.
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

        let scale: CGFloat = zooms && isLeaving ? Self.zoomedIn : 1

        // Only offset, scale and opacity change, so the hub's photo background keeps covering the safe areas.
        return content()
            // No page has a text field of its own; text is edited in sheets and alerts. Without this, every page
            // in the stack re-lays out around the keyboard (grids, panorama, safe-area measurements), which hung
            // the app while the note editor's keyboard came up.
            .ignoresSafeArea(.keyboard)
            // A zooming page scatters its items when covered and turns them in as it opens, once the page it opened
            // from has gone.
            .featherScope(itemState)
            .environment(\.featherFromBack, depth == 0)
            .environment(\.zoomPageDepth, depth)
            .coordinateSpace(.named(Feather.pageSpace))
            .offset(x: isTop ? backProgress * width : 0)
            .scaleEffect(scale)
            .animation(Self.zoomAnimation, value: isLeaving)
            .animation(Self.zoomAnimation, value: isCovered)
            // A waiting page needs no hiding of its own: its lines haven't turned in yet, and its background shows as
            // they start.
            .opacity(opacity)
            // Leaving and covered pages keep their background until their items have moved away.
            .animation(isLeaving ? .easeIn(duration: 0.12).delay(Feather.exitTime - 0.12) : MetroMotion.standard, value: isLeaving)
            // A zooming page's background goes as its items finish scattering, leaving a moment of dark before the
            // next page, as on Windows.
            .animation(isCovered ? (zooms ? .easeIn(duration: 0.1).delay(0.3) : .easeIn(duration: 0.1).delay(Feather.coverFadeDelay)) : MetroMotion.standard, value: isCovered)
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
