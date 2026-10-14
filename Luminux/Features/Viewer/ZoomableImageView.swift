import PhotosUI
import SwiftUI
import UIKit
import VisionKit

/// Pinch and double-tap zoom on a photo; a single tap toggles the viewer chrome. Touch and hold lifts the subject
/// (a person, pet or object) to copy, share or drag, like Photos.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage?
    var isCurrent: Bool
    /// Subject lifting is a Pro feature; while it's locked, holding the photo offers it instead.
    var allowsLift = false
    var lifter: SubjectLifter?
    var onSingleTap: () -> Void
    var onZoomChange: (Bool) -> Void = { _ in }
    var onLockedLift: () -> Void = {}
    /// True while a lifted subject is highlighted, so the viewer can hold still.
    var onSubjectHighlight: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        update(view)
        return view
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        update(view)
    }

    private func update(_ view: ZoomingScrollView) {
        view.onSingleTap = onSingleTap
        view.onZoomChange = onZoomChange
        view.onLockedLift = onLockedLift
        view.onSubjectHighlight = onSubjectHighlight
        lifter?.view = view
        view.setImage(image)
        view.updateLift(isCurrent: isCurrent, allowsLift: allowsLift)
        if !isCurrent { view.resetZoom(animated: false) }
    }
}

/// Lets SwiftUI ask the photo view for its subject, for the VoiceOver action.
@MainActor
final class SubjectLifter {
    weak var view: ZoomingScrollView?

    func copySubject() async -> Bool {
        await view?.copySubject() ?? false
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate, ImageAnalysisInteractionDelegate {
    var onSingleTap: () -> Void = {}
    var onZoomChange: (Bool) -> Void = { _ in }
    var onLockedLift: () -> Void = {}
    var onSubjectHighlight: (Bool) -> Void = { _ in }
    private var wasZoomed = false
    private let imageView = UIImageView()
    private let liftInteraction = ImageAnalysisInteraction()
    private let lockedPress = UILongPressGestureRecognizer()
    private var analysisTask: Task<Void, Never>?
    private weak var analyzedImage: UIImage?
    private var isHighlighting = false

    private static let analyzer = ImageAnalyzer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        imageView.isUserInteractionEnabled = true
        liftInteraction.delegate = self
        liftInteraction.preferredInteractionTypes = []
        imageView.addInteraction(liftInteraction)
        lockedPress.minimumPressDuration = 0.5
        lockedPress.addTarget(self, action: #selector(handleLockedPress(_:)))
        lockedPress.isEnabled = false
        imageView.addGestureRecognizer(lockedPress)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setImage(_ image: UIImage?) {
        guard imageView.image !== image else { return }
        imageView.image = image
        analysisTask?.cancel()
        liftInteraction.analysis = nil
        analyzedImage = nil
        setNeedsLayout()
    }

    /// Analyses the current photo for subjects once lifting is allowed; other pages and locked lifting skip the work.
    func updateLift(isCurrent: Bool, allowsLift: Bool) {
        let isSupported = ImageAnalyzer.isSupported
        liftInteraction.preferredInteractionTypes = allowsLift && isSupported ? .imageSubject : []
        lockedPress.isEnabled = !allowsLift && isSupported && isCurrent
        guard allowsLift, isCurrent, isSupported, let image = imageView.image, analyzedImage !== image else { return }
        analyzedImage = image
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            let analysis = try? await Self.analyzer.analyze(image, configuration: ImageAnalyzer.Configuration([.visualLookUp]))
            guard let self, !Task.isCancelled, self.imageView.image === image else { return }
            self.liftInteraction.analysis = analysis
        }
    }

    func copySubject() async -> Bool {
        // The interaction's own image of all subjects, so nothing non-Sendable leaves the main actor.
        let subjects = await liftInteraction.subjects
        guard !subjects.isEmpty, let image = try? await liftInteraction.image(for: subjects) else { return false }
        UIPasteboard.general.image = image
        return true
    }

    func interaction(_ interaction: ImageAnalysisInteraction, highlightSelectedItemsDidChange highlightSelectedItems: Bool) {
        isHighlighting = highlightSelectedItems
        onSubjectHighlight(highlightSelectedItems)
    }

    func resetZoom(animated: Bool) {
        if zoomScale != minimumZoomScale { setZoomScale(minimumZoomScale, animated: animated) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard zoomScale == minimumZoomScale else {
            centerImage()
            return
        }
        imageView.frame = fittedFrame()
        contentSize = bounds.size
        centerImage()
    }

    private func fittedFrame() -> CGRect {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    private func centerImage() {
        let insetX = max((bounds.width - imageView.frame.width) / 2, 0)
        let insetY = max((bounds.height - imageView.frame.height) / 2, 0)
        imageView.frame.origin = CGPoint(
            x: zoomScale == minimumZoomScale ? imageView.frame.origin.x : insetX,
            y: zoomScale == minimumZoomScale ? imageView.frame.origin.y : insetY
        )
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Keep the photo centred while it is smaller than the screen.
        let offsetX = max((bounds.width - contentSize.width) / 2, 0)
        let offsetY = max((bounds.height - contentSize.height) / 2, 0)
        imageView.center = CGPoint(x: contentSize.width / 2 + offsetX, y: contentSize.height / 2 + offsetY)

        let isZoomed = zoomScale > minimumZoomScale + 0.01
        if isZoomed != wasZoomed {
            wasZoomed = isZoomed
            onZoomChange(isZoomed)
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let scale = min(maximumZoomScale, 2.5)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func handleSingleTap() {
        // A tap while a subject is lifted just puts it down.
        if isHighlighting {
            liftInteraction.highlightedSubjects = []
            return
        }
        onSingleTap()
    }

    @objc private func handleLockedPress(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began { onLockedLift() }
    }
}

/// A Live Photo that plays its motion once each time it becomes the current photo.
struct LivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto?
    var playsOnShow: Bool

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        let isNew = view.livePhoto !== livePhoto
        view.livePhoto = livePhoto
        if isNew, playsOnShow, livePhoto != nil {
            view.startPlayback(with: .full)
        }
    }
}

/// Vertical drag on the viewer: down closes it, up reveals details. Starts only on a mostly vertical pan so paging and zoomed panning keep working.
struct VerticalDragRecognizer: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onChange: (_ translation: CGFloat) -> Void
    var onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).y
        switch recognizer.state {
        case .changed: onChange(translation)
        case .ended, .cancelled, .failed: onEnd(translation, recognizer.velocity(in: recognizer.view).y)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x) * 1.2
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
