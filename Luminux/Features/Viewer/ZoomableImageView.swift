import PhotosUI
import SwiftUI
import UIKit

/// Pinch and double-tap zoom on a photo; a single tap toggles the viewer chrome.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage?
    var isCurrent: Bool
    var onSingleTap: () -> Void
    var onZoomChange: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.onSingleTap = onSingleTap
        view.onZoomChange = onZoomChange
        return view
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.onSingleTap = onSingleTap
        view.onZoomChange = onZoomChange
        view.setImage(image)
        if !isCurrent { view.resetZoom(animated: false) }
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    var onSingleTap: () -> Void = {}
    var onZoomChange: (Bool) -> Void = { _ in }
    private var wasZoomed = false
    private let imageView = UIImageView()

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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setImage(_ image: UIImage?) {
        guard imageView.image !== image else { return }
        imageView.image = image
        setNeedsLayout()
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

    @objc private func handleSingleTap() { onSingleTap() }
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
