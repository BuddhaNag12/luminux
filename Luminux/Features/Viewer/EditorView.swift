import Photos
import SwiftUI

/// Crop, adjust and looks, saved as a PhotoKit edit that reopens with its sliders where they were left
/// (and reverts here or in Photos). With iPhone Duo open or half-folded, the photo takes the top of the screen and the
/// controls spread over the bottom.
struct EditorView: View {
    let asset: PHAsset

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.metro) private var metro
    @Environment(\.dismiss) private var dismiss
    @Environment(\.splitY) private var splitY
    @State private var session: EditSession?
    /// Where the photo area starts, so it can end on the split line.
    @State private var photoTop: CGFloat = 0
    @State private var recipe = EditRecipe()
    @State private var preview: UIImage?
    /// Whether `preview` was rendered with the crop applied; the crop handles only fit an uncropped preview.
    @State private var previewIsCropped = false
    @State private var mode: EditMode = .adjust
    @State private var selected: Adjustment = .exposure
    @State private var aspect: CropAspect = .free
    @State private var showsOriginal = false
    @State private var lookThumbnails: [Look?: UIImage] = [:]
    @State private var isRendering = false
    @State private var needsRender = false
    @State private var isSaving = false
    @State private var failed = false
    @State private var couldNotOpen = false
    @State private var isAppBarExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LUMINUX").font(.metroOverline).tracking(1.5).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
                    if mode == .crop && !previewIsCropped {
                        CropOverlay(crop: $recipe.crop, aspect: aspect, imageRect: imageRect, imageSize: preview.size)
                    }
                } else if couldNotOpen {
                    Text("Couldn't open this photo for editing.")
                        .font(.metroBody)
                        .foregroundStyle(metro.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MetroProgress().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            // Touch and hold to compare with the photo before adjustments.
            .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 40) {} onPressingChanged: { pressing in
                if mode != .crop { showsOriginal = pressing }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(showsOriginal ? "Original photo" : "Edited photo")
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { photoTop = $0 }
            .frame(height: splitY.map { max($0 - photoTop, 120) })
            .padding(.vertical, 12)

            modeRow
                .padding(.bottom, 10)

            Group {
                switch mode {
                case .crop: aspectRow
                case .adjust: if splitY == nil { adjustControls } else { allAdjustments }
                case .looks: if splitY == nil { looksRow } else { looksGrid }
                }
            }
            // A fixed height keeps the photo still as the mode changes; split, the controls fill the bottom half.
            .frame(height: splitY == nil ? 96 : nil, alignment: .top)
            .frame(maxHeight: splitY == nil ? nil : .infinity, alignment: .top)
            .disabled(session == nil)

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
                AppBarButton(title: "rotate", systemImage: "rotate.left", isEnabled: session != nil) { rotate() },
                AppBarButton(title: "save", systemImage: "checkmark", isEnabled: !isSaving && session != nil) { save() },
                AppBarButton(title: "cancel", systemImage: "xmark") { dismiss() },
            ],
            menu: menu,
            isExpanded: $isAppBarExpanded
        )
        .overlay {
            if isSaving {
                metro.background.opacity(0.6).ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 12) {
                            MetroProgress()
                            Text("saving").font(.metroBody)
                        }
                    }
            }
        }
        .task {
            do {
                let session = try await library.editSession(for: asset)
                self.session = session
                recipe = session.recipe
                if let look = recipe.look, look.adjustments == recipe.adjustments { mode = .looks }
                requestRender()
                await renderLookThumbnails(from: session.preview)
            } catch {
                couldNotOpen = true
            }
        }
        .onChange(of: renderKey) { requestRender() }
    }

    // MARK: Controls

    private var modeRow: some View {
        HStack(spacing: 24) {
            ForEach(EditMode.allCases) { option in
                Button(option.rawValue) {
                    withAnimation(MetroMotion.fade) { mode = option }
                }
                .font(.metro(24, .semilight))
                .foregroundStyle(option == mode ? metro.foreground : metro.secondary)
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == mode ? .isSelected : [])
            }
        }
    }

    private var aspectRow: some View {
        HStack(spacing: 20) {
            ForEach(CropAspect.allCases) { option in
                Button(option.title) { setAspect(option) }
                    .font(.metro(17, .semilight))
                    .foregroundStyle(option == aspect ? metro.accentColor : metro.foreground)
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == aspect ? .isSelected : [])
            }
        }
    }

    private var adjustControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(Adjustment.allCases) { adjustment in
                        Button {
                            selected = adjustment
                        } label: {
                            HStack(spacing: 4) {
                                Text(adjustment.title)
                                // Marks the sliders that have been moved.
                                if recipe.adjustments[adjustment] != 0 {
                                    Rectangle().fill(metro.accentColor).frame(width: 5, height: 5)
                                }
                            }
                            .font(.metro(17, .semilight))
                            .foregroundStyle(adjustment == selected ? metro.accentColor : metro.foreground)
                            .frame(minHeight: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(adjustment == selected ? .isSelected : [])
                        .accessibilityValue(recipe.adjustments[adjustment] == 0 ? "" : percent(recipe.adjustments[adjustment]))
                    }
                }
            }
            .scrollIndicators(.hidden)

            slider(selected)
        }
    }

    /// Every adjustment at once, each with its own slider, when there's room for them all.
    private var allAdjustments: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Adjustment.allCases) { adjustment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(adjustment.title)
                            .font(.metro(17, .semilight))
                            .foregroundStyle(recipe.adjustments[adjustment] == 0 ? metro.foreground : metro.accentColor)
                        slider(adjustment)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func slider(_ adjustment: Adjustment) -> some View {
        HStack(spacing: 12) {
            MetroSlider(
                label: adjustment.title,
                value: Binding {
                    recipe.adjustments[adjustment]
                } set: {
                    recipe.adjustments[adjustment] = $0
                    recipe.look = nil
                },
                range: adjustment.range,
                resting: 0
            )
            Text(percent(recipe.adjustments[adjustment]))
                .font(.metroCaption)
                .monospacedDigit()
                .foregroundStyle(metro.secondary)
                .frame(width: 40, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var looksRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                lookTile(nil, title: "none")
                ForEach(Look.allCases) { look in
                    lookTile(look, title: look.rawValue)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// The looks as a grid of larger tiles, when there's room.
    private var looksGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 10) {
                lookTile(nil, title: "none", fills: true)
                ForEach(Look.allCases) { look in
                    lookTile(look, title: look.rawValue, fills: true)
                }
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func lookTile(_ look: Look?, title: String, fills: Bool = false) -> some View {
        let isSelected = look == nil ? recipe.adjustments.isNeutral : recipe.look == look
        return Button {
            recipe.adjustments = look?.adjustments ?? Adjustments()
            recipe.look = look
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Color.clear
                    .overlay {
                        if let thumbnail = lookThumbnails[look] {
                            Image(uiImage: thumbnail).resizable().scaledToFill()
                        } else {
                            metro.chrome
                        }
                    }
                    .frame(width: fills ? nil : 64, height: fills ? nil : 64)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                .overlay {
                    if isSelected { Rectangle().strokeBorder(metro.accentColor, lineWidth: 3) }
                }
                Text(title)
                    .font(.metroCaption)
                    .foregroundStyle(isSelected ? metro.accentColor : metro.foreground)
            }
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var menu: [AppBarMenuItem] {
        var items = [AppBarMenuItem(title: "reset all", isEnabled: !recipe.isIdentity) { resetAll() }]
        if asset.hasAdjustments {
            items.append(AppBarMenuItem(title: "revert to original") { revert() })
        }
        return items
    }

    private func percent(_ value: Double) -> String {
        let rounded = Int((value * 100).rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    // MARK: Rendering

    private struct RenderKey: Equatable {
        var recipe: EditRecipe
        var includesCrop: Bool
        var original: Bool
    }

    private var renderKey: RenderKey {
        RenderKey(recipe: recipe, includesCrop: mode != .crop, original: showsOriginal)
    }

    /// Renders the newest state once the previous render finishes, so a slider drag never queues up renders.
    private func requestRender() {
        guard session != nil else { return }
        guard !isRendering else {
            needsRender = true
            return
        }
        isRendering = true
        Task {
            repeat {
                needsRender = false
                guard let session else { break }
                var key = renderKey
                if key.original { key.recipe.adjustments = Adjustments() }
                let source = UncheckedBox(value: session.preview)
                let rendered = await Task.detached(priority: .userInitiated) { [key] in
                    PhotoEditing.preview(of: source.value, recipe: key.recipe, includingCrop: key.includesCrop).map(UncheckedBox.init)
                }.value
                if let rendered {
                    preview = rendered.value
                    previewIsCropped = key.includesCrop
                }
            } while needsRender
            isRendering = false
        }
    }

    private func renderLookThumbnails(from image: CIImage) async {
        let scale = 160 / max(image.extent.width, image.extent.height)
        let small = UncheckedBox(value: image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        let looks: [Look?] = [nil] + Look.allCases
        for look in looks {
            let recipe = EditRecipe(adjustments: look?.adjustments ?? Adjustments())
            let thumbnail = await Task.detached(priority: .utility) {
                PhotoEditing.preview(of: small.value, recipe: recipe, includingCrop: false).map(UncheckedBox.init)
            }.value
            lookThumbnails[look] = thumbnail?.value
        }
    }

    // MARK: Actions

    /// The rotated photo's size before cropping, for fitting crop ratios.
    private var rotatedSize: CGSize {
        guard let extent = session?.preview.extent.size else { return .zero }
        return recipe.quarterTurns % 2 == 0 ? extent : CGSize(width: extent.height, height: extent.width)
    }

    private func fittedRect(for size: CGSize, in bounds: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    private func rotate() {
        recipe = recipe.rotatedLeft()
        if aspect != .free { setAspect(aspect) }
    }

    private func resetAll() {
        recipe = EditRecipe()
        aspect = .free
    }

    private func setAspect(_ option: CropAspect) {
        aspect = option
        guard let ratio = option.ratio(for: rotatedSize) else {
            recipe.crop = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        recipe.crop = CropMath.centered(ratio: ratio, imageSize: rotatedSize)
    }

    private func save() {
        guard let session else { return }
        guard recipe != session.recipe else {
            dismiss()
            return
        }
        isSaving = true
        failed = false
        Task {
            do {
                try await library.applyEdit(recipe, in: session)
                dismiss()
            } catch {
                failed = true
            }
            isSaving = false
        }
    }

    private func revert() {
        isSaving = true
        Task {
            do {
                try await library.revertEdits(asset)
                dismiss()
            } catch {
                failed = true
            }
            isSaving = false
        }
    }
}

enum EditMode: String, CaseIterable, Identifiable {
    case crop, adjust, looks
    var id: String { rawValue }
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
