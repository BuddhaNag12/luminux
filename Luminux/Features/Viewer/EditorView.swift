import Photos
import SwiftUI

/// Rotate and crop, saved as a non-destructive PhotoKit edit (revertible here or in Photos).
struct EditorView: View {
    let asset: PHAsset

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.metro) private var metro
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var source: UIImage?
    @State private var preview: UIImage?
    @State private var quarterTurns = 0
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect: CropAspect = .free
    @State private var isSaving = false
    @State private var failed = false
    @State private var isAppBarExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LUMINUX").font(.metroOverline).tracking(1.5)
            Text("edit")
                .font(.metroTitle)
                .padding(.leading, -3)

            GeometryReader { geo in
                if let preview {
                    let imageRect = fittedRect(for: preview.size, in: geo.size)
                    Image(uiImage: preview)
                        .resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                    CropOverlay(crop: $crop, aspect: aspect, imageRect: imageRect, imageSize: preview.size)
                } else {
                    ProgressView().tint(metro.accentColor).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.vertical, 12)

            HStack(spacing: 20) {
                ForEach(CropAspect.allCases) { option in
                    Button(option.title) { setAspect(option) }
                        .font(.metro(17, .semilight))
                        .foregroundStyle(option == aspect ? metro.accentColor : metro.foreground)
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == aspect ? .isSelected : [])
                }
            }
            .padding(.bottom, 12)

            if failed {
                Text("Couldn't save this edit. Try again.")
                    .font(.metroCaption)
                    .foregroundStyle(metro.secondary)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, MetroMetrics.margin + 12)
        .padding(.top, 16)
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .metroAppBar(
            [
                AppBarButton(title: "rotate", systemImage: "rotate.left") { rotate() },
                AppBarButton(title: "save", systemImage: "checkmark", isEnabled: !isSaving && preview != nil) { save() },
                AppBarButton(title: "cancel", systemImage: "xmark") { dismiss() },
            ],
            menu: [AppBarMenuItem(title: "reset") { reset() }],
            isExpanded: $isAppBarExpanded
        )
        .overlay {
            if isSaving {
                metro.background.opacity(0.6).ignoresSafeArea()
                    .overlay { ProgressView("saving").tint(metro.accentColor).font(.metroBody) }
            }
        }
        .task {
            let side = 1200 * displayScale
            for await image in ImageLoader.shared.images(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit) {
                source = image
                preview = image
            }
        }
    }

    private func fittedRect(for size: CGSize, in bounds: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    private func rotate() {
        quarterTurns = (quarterTurns + 1) % 4
        guard let source else { return }
        preview = PhotoEditing.preview(of: source, quarterTurns: quarterTurns)
        setAspect(aspect)
    }

    private func reset() {
        quarterTurns = 0
        preview = source
        aspect = .free
        crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private func setAspect(_ option: CropAspect) {
        aspect = option
        guard let size = preview?.size, let ratio = option.ratio(for: size) else {
            crop = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        crop = CropMath.centered(ratio: ratio, imageSize: size)
    }

    private func save() {
        let recipe = EditRecipe(quarterTurns: quarterTurns, crop: crop)
        guard !recipe.isIdentity else {
            dismiss()
            return
        }
        isSaving = true
        failed = false
        Task {
            do {
                try await library.applyEdit(recipe, to: asset)
                dismiss()
            } catch {
                failed = true
            }
            isSaving = false
        }
    }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, square, wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "free"
        case .original: "original"
        case .square: "square"
        case .wide: "16:9"
        }
    }

    /// Width over height in pixels; nil leaves the crop unconstrained.
    func ratio(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: imageSize.width / max(imageSize.height, 1)
        case .square: 1
        case .wide: imageSize.width >= imageSize.height ? 16 / 9 : 9 / 16
        }
    }
}

nonisolated enum CropMath {
    static let minimumSide: CGFloat = 0.1

    /// The largest centered crop with the given pixel ratio.
    static func centered(ratio: CGFloat, imageSize: CGSize) -> CGRect {
        let imageRatio = imageSize.width / max(imageSize.height, 1)
        if ratio >= imageRatio {
            let height = imageRatio / ratio
            return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        } else {
            let width = ratio / imageRatio
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }
    }

    /// Moves one corner to `point` (normalized), keeping the opposite corner fixed and an optional pixel ratio.
    static func drag(_ crop: CGRect, corner: UnitPoint, to point: CGPoint, ratio: CGFloat?, imageSize: CGSize) -> CGRect {
        let anchor = CGPoint(x: corner.x == 0 ? crop.maxX : crop.minX, y: corner.y == 0 ? crop.maxY : crop.minY)
        let x = min(max(point.x, 0), 1)
        let y = min(max(point.y, 0), 1)
        var width = max(abs(x - anchor.x), minimumSide)
        var height = max(abs(y - anchor.y), minimumSide)

        if let ratio {
            // Normalized height for a given normalized width at this pixel ratio.
            let factor = imageSize.width / max(imageSize.height, 1) / ratio
            height = width * factor
            let maxWidth = corner.x == 0 ? anchor.x : 1 - anchor.x
            let maxHeight = corner.y == 0 ? anchor.y : 1 - anchor.y
            if height > maxHeight {
                height = maxHeight
                width = height / factor
            }
            width = min(width, maxWidth)
        }

        let originX = corner.x == 0 ? anchor.x - width : anchor.x
        let originY = corner.y == 0 ? anchor.y - height : anchor.y
        return CGRect(x: originX, y: originY, width: width, height: height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Slides the crop by a normalized offset, staying inside the image.
    static func move(_ crop: CGRect, by offset: CGSize) -> CGRect {
        var moved = crop.offsetBy(dx: offset.width, dy: offset.height)
        moved.origin.x = min(max(moved.minX, 0), 1 - moved.width)
        moved.origin.y = min(max(moved.minY, 0), 1 - moved.height)
        return moved
    }
}

private struct CropOverlay: View {
    @Binding var crop: CGRect
    let aspect: CropAspect
    let imageRect: CGRect
    let imageSize: CGSize

    @State private var dragStart: CGRect?

    private var frame: CGRect {
        CGRect(
            x: imageRect.minX + crop.minX * imageRect.width,
            y: imageRect.minY + crop.minY * imageRect.height,
            width: crop.width * imageRect.width,
            height: crop.height * imageRect.height
        )
    }

    var body: some View {
        ZStack {
            Path { path in
                path.addRect(imageRect)
                path.addRect(frame)
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(.white, lineWidth: 1)
                .frame(width: frame.width, height: frame.height)
                .contentShape(Rectangle())
                .position(x: frame.midX, y: frame.midY)
                .gesture(moveGesture)
                .accessibilityLabel("Crop area")

            ForEach([UnitPoint.topLeading, .topTrailing, .bottomLeading, .bottomTrailing], id: \.self) { corner in
                CornerHandle(corner: corner)
                    .position(x: frame.minX + corner.x * frame.width, y: frame.minY + corner.y * frame.height)
                    .gesture(cornerGesture(corner))
            }
        }
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                crop = CropMath.move(start, by: CGSize(
                    width: value.translation.width / imageRect.width,
                    height: value.translation.height / imageRect.height
                ))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func cornerGesture(_ corner: UnitPoint) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                let startCorner = CGPoint(x: start.minX + corner.x * start.width, y: start.minY + corner.y * start.height)
                let point = CGPoint(
                    x: startCorner.x + value.translation.width / imageRect.width,
                    y: startCorner.y + value.translation.height / imageRect.height
                )
                crop = CropMath.drag(start, corner: corner, to: point, ratio: aspect.ratio(for: imageSize), imageSize: imageSize)
            }
            .onEnded { _ in dragStart = nil }
    }
}

private struct CornerHandle: View {
    let corner: UnitPoint

    var body: some View {
        Path { path in
            let length: CGFloat = 18
            let horizontal: CGFloat = corner.x == 0 ? 1 : -1
            let vertical: CGFloat = corner.y == 0 ? 1 : -1
            path.move(to: CGPoint(x: 22 + horizontal * length, y: 22))
            path.addLine(to: CGPoint(x: 22, y: 22))
            path.addLine(to: CGPoint(x: 22, y: 22 + vertical * length))
        }
        .stroke(.white, lineWidth: 4)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}
