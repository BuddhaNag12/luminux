import Photos
import SwiftUI

/// Crop, light, colour, effects and looks, saved as a PhotoKit edit that reopens with its values where they were left
/// (and reverts here or in Photos). Each adjustment is changed on a ruler dial, or by swiping across the photo; holding
/// the photo, or the compare button, shows the original.
///
/// One editor for every screen: on iPhone the tools sit under the photo; on iPhone Duo half-folded the photo takes the
/// raised half and the tools the flat one; open flat and wide, photo and tools sit side by side.
struct EditorView: View {
    let asset: PHAsset

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.metro) private var metro
    @Environment(\.dismiss) private var dismiss
    @Environment(\.splitY) private var splitY
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var session: EditSession?
    @State private var recipe = EditRecipe()
    @State private var preview: UIImage?
    /// Whether `preview` was rendered with the crop applied; the crop handles only fit an uncropped preview.
    @State private var previewIsCropped = false
    @State private var mode: EditMode = .crop
    /// The adjustment last picked in each group, so switching groups and back returns to it.
    @State private var selected: [AdjustmentGroup: Adjustment] = [:]
    @State private var aspect: CropAspect = .free
    /// The crop shape's orientation when picked by hand; nil follows the photo's.
    @State private var cropLandscape: Bool?
    @State private var isLevelling = false
    /// A turn or flip waiting for its new preview, so the photo can animate into it.
    @State private var pendingTurn: PhotoTurn?
    /// 1 when the new preview is shown turned back to where the old one was, easing to 0.
    @State private var turnProgress: Double = 0
    @State private var flipProgress: Double = 0
    /// The crop handles wait until the photo has turned into place.
    @State private var isTurning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum PhotoTurn { case rotate, flip }
    /// Said under the crop tools for a moment, e.g. when auto finds no horizon.
    @State private var cropNote: String?
    /// Held down on the photo.
    @State private var showsOriginal = false
    /// The compare button keeps the original showing.
    @State private var pinsOriginal = false
    /// The value a swipe across the photo started from, while one is under way.
    @State private var swipeStart: Double?
    @State private var lookThumbnails: [Look?: UIImage] = [:]
    @State private var isRendering = false
    @State private var needsRender = false
    @State private var isSaving = false
    @State private var failed = false
    @State private var couldNotOpen = false
    @State private var isAppBarExpanded = false
    @State private var size: CGSize = .zero
    /// Where the photo starts, so it can end on the split line.
    @State private var photoTop: CGFloat = 0

    private enum Arrangement {
        /// iPhone, and iPhone Duo closed: tools under the photo.
        case stacked
        /// iPhone Duo half-folded or open upright: the photo above the line, the tools below.
        case split(CGFloat)
        /// iPhone Duo open flat and wide: photo and tools side by side.
        case sideBySide
    }

    private var arrangement: Arrangement {
        if sizeClass == .regular, size.width > size.height { return .sideBySide }
        if let splitY { return .split(splitY) }
        return .stacked
    }

    private var isRoomy: Bool {
        if case .stacked = arrangement { return false }
        return true
    }

    /// The adjustment the dial and a swipe change; nil in crop and looks.
    private var active: Adjustment? {
        mode.group.map { selected[$0] ?? $0.adjustments[0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LUMINUX").font(.metroOverline).tracking(1.5).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Text("edit")
                .font(.metroTitle)
                .padding(.leading, -3)

            switch arrangement {
            case .stacked:
                photoPane
                    .padding(.vertical, 12)
                toolPanel
                    // A fixed height keeps the photo still as the tools change.
                    .frame(height: 188, alignment: .top)
                    .padding(.bottom, 8)
            case .split(let line):
                photoPane
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { photoTop = $0 }
                    // Ends a little above the line, and the tools start well below it: nothing to touch in the fold.
                    .frame(height: max(line - photoTop - 8, 120))
                    .padding(.top, 12)
                toolPanel
                    .padding(.top, 28)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .sideBySide:
                HStack(alignment: .top, spacing: 40) {
                    photoPane
                    toolPanel
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.top, 12)
            }

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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .metroAppBar(
            [
                AppBarButton(id: "compare", title: pinsOriginal ? "edited" : "compare", systemImage: pinsOriginal ? "eye.slash" : "eye", isEnabled: session != nil) {
                    pinsOriginal.toggle()
                },
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
                requestRender()
                await renderLookThumbnails(from: session.preview)
            } catch {
                couldNotOpen = true
            }
        }
        .onChange(of: renderKey) { requestRender() }
    }

    // MARK: Photo

    private var photoPane: some View {
        GeometryReader { geo in
            if let preview {
                let imageRect = fittedRect(for: preview.size, in: geo.size)
                // Turned back a quarter, the new photo sits as the old one did; this scale matches the old size.
                let turnedBack = fittedRect(for: CGSize(width: preview.size.height, height: preview.size.width), in: geo.size)
                let startScale = turnedBack.width / max(imageRect.height, 1)
                Image(uiImage: preview)
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    // A flip swings the photo round like a card; a rotate turns it a quarter into place.
                    .scaleEffect(x: 1 - 2 * flipProgress, y: 1)
                    .rotationEffect(.degrees(90 * turnProgress))
                    .scaleEffect(1 + (startScale - 1) * turnProgress)
                    .position(x: imageRect.midX, y: imageRect.midY)
                if mode == .crop && !previewIsCropped && !isTurning {
                    CropOverlay(crop: $recipe.crop, ratio: cropRatio, imageRect: imageRect, imageSize: preview.size)
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
            if mode != .crop && swipeStart == nil { showsOriginal = pressing }
        }
        // Swiping across the photo nudges the adjustment on the dial, like Snapseed.
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag in
                    guard let active, abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    let start = swipeStart ?? recipe.adjustments[active]
                    swipeStart = start
                    showsOriginal = false
                    // Rightward raises it; the dial's own drag runs the other way, as its ruler moves with the finger.
                    value(of: active).wrappedValue = MetroDial.value(from: start, dragged: -drag.translation.width, range: active.range, resting: 0)
                }
                .onEnded { _ in swipeStart = nil },
            including: mode == .crop ? .subviews : .all
        )
        .overlay(alignment: .top) {
            if swipeStart != nil, let active {
                Text("\(active.title) \(MetroDial.text(for: recipe.adjustments[active]))")
                    .font(.metro(17, .semilight))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(metro.background.opacity(0.75))
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(MetroMotion.fade, value: swipeStart == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(showsOriginal || pinsOriginal ? "Original photo" : "Edited photo")
    }

    // MARK: Tools

    private var toolPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            modeRow
            Group {
                switch mode {
                case .crop: cropControls
                case .looks: isRoomy ? AnyView(looksGrid) : AnyView(looksRow)
                default:
                    if let group = mode.group, let active {
                        adjustmentChips(group)
                        MetroDial(label: active.title, value: value(of: active), range: active.range, resting: 0)
                            .padding(.top, isRoomy ? 8 : 0)
                    }
                }
            }
            .disabled(session == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 22) {
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
        .scrollIndicators(.hidden)
    }

    /// Rotate, flip, auto-straighten and the crop shapes as tiles, over a ruler for straightening, like Photos and
    /// Snapseed.
    private var cropControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isRoomy {
                HStack(spacing: 6) { cropTools }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], alignment: .leading, spacing: 6) {
                    aspectTiles
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        cropTools
                        Rectangle().fill(metro.secondary.opacity(0.4)).frame(width: 1, height: 36).padding(.horizontal, 4)
                        aspectTiles
                    }
                }
                .scrollIndicators(.hidden)
            }
            MetroDial(
                label: "straighten",
                value: Binding { recipe.straighten } set: { recipe.straighten = $0 },
                range: EditRecipe.straightenRange,
                ticks: 90,
                format: { MetroDial.degrees($0) }
            )
            .padding(.top, isRoomy ? 8 : 0)
            if let cropNote {
                Text(cropNote)
                    .font(.metroCaption)
                    .foregroundStyle(metro.secondary)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var cropTools: some View {
        cropTile("rotate", systemImage: "rotate.left") { rotate() }
        cropTile("flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
            pendingTurn = .flip
            recipe = recipe.flippedHorizontally()
        }
        cropTile(isLevelling ? "levelling" : "auto", systemImage: "level", isEnabled: !isLevelling) { level() }
        cropTile(isLandscapeCrop ? "landscape" : "portrait", systemImage: isLandscapeCrop ? "rectangle" : "rectangle.portrait",
                 isEnabled: aspect != .free && aspect != .square) {
            cropLandscape = !isLandscapeCrop
            setAspect(aspect)
        }
        cropTile("reset", systemImage: "arrow.counterclockwise", isEnabled: !recipe.hasNoGeometry) { resetGeometry() }
    }

    private var aspectTiles: some View {
        ForEach(CropAspect.allCases) { option in
            Button { setAspect(option) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    aspectShape(option)
                    Text(option.title)
                        .font(.metro(14, .semilight))
                        .lineLimit(1)
                }
                .padding(8)
                .frame(minWidth: 68, maxWidth: isRoomy ? .infinity : nil, minHeight: 52, alignment: .topLeading)
                .foregroundStyle(option == aspect ? metro.onAccent : metro.foreground)
                .background(option == aspect ? metro.accentColor : metro.chrome)
            }
            .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
            .accessibilityLabel(option == .free ? "free crop" : "\(option.title) crop")
            .accessibilityAddTraits(option == aspect ? .isSelected : [])
        }
    }

    /// A small outline of the crop shape, turned the way the crop is.
    private func aspectShape(_ option: CropAspect) -> some View {
        let ratio = option.ratio(for: rotatedSize, landscape: isLandscapeCrop) ?? 1
        let side: CGFloat = 16
        return Rectangle()
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: option == .free ? [3, 2] : []))
            .frame(width: ratio >= 1 ? side : side * ratio, height: ratio >= 1 ? side / ratio : side)
            .frame(width: side, height: side, alignment: .leading)
    }

    private func cropTile(_ title: String, systemImage: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .light))
                    .frame(height: 16)
                Text(title)
                    .font(.metro(14, .semilight))
                    .lineLimit(1)
            }
            .padding(8)
            .frame(minWidth: 68, maxWidth: isRoomy ? .infinity : nil, minHeight: 52, alignment: .topLeading)
            .foregroundStyle(metro.foreground)
            .background(metro.chrome)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    /// The group's adjustments as tiles, each showing its value; the picked one is on the dial.
    @ViewBuilder
    private func adjustmentChips(_ group: AdjustmentGroup) -> some View {
        if isRoomy {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(group.adjustments) { chip($0, in: group) }
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(group.adjustments) { chip($0, in: group) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(_ adjustment: Adjustment, in group: AdjustmentGroup) -> some View {
        let isActive = adjustment == active
        let amount = recipe.adjustments[adjustment]
        return Button {
            withAnimation(MetroMotion.snappy) { selected[group] = adjustment }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(adjustment.title)
                    .font(.metro(15, .semilight))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(amount == 0 ? " " : MetroDial.text(for: amount))
                    .font(.metroCaption)
                    .monospacedDigit()
                    .opacity(0.85)
            }
            .padding(8)
            .frame(minWidth: 92, maxWidth: isRoomy ? .infinity : nil, minHeight: 52, alignment: .topLeading)
            .foregroundStyle(isActive ? metro.onAccent : metro.foreground)
            .background(isActive ? metro.accentColor : metro.chrome)
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .accessibilityLabel(adjustment.title)
        .accessibilityValue(amount == 0 ? "" : percent(amount))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func value(of adjustment: Adjustment) -> Binding<Double> {
        Binding {
            recipe.adjustments[adjustment]
        } set: {
            recipe.adjustments[adjustment] = $0
            recipe.look = nil
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
        RenderKey(recipe: recipe, includesCrop: mode != .crop, original: showsOriginal || pinsOriginal)
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
                    if let turn = pendingTurn, !reduceMotion {
                        pendingTurn = nil
                        // Show the new photo turned back to where the old one was, then let it turn into place.
                        var instant = Transaction()
                        instant.disablesAnimations = true
                        withTransaction(instant) {
                            preview = rendered.value
                            previewIsCropped = key.includesCrop
                            if turn == .rotate { turnProgress = 1 } else { flipProgress = 1 }
                            isTurning = true
                        }
                        withAnimation(.timingCurve(Feather.decelerate, duration: turn == .rotate ? 0.4 : 0.45)) {
                            turnProgress = 0
                            flipProgress = 0
                        } completion: {
                            withAnimation(MetroMotion.fade) { isTurning = false }
                        }
                    } else {
                        preview = rendered.value
                        previewIsCropped = key.includesCrop
                    }
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
        pendingTurn = .rotate
        recipe = recipe.rotatedLeft()
        // The photo turned, so a shape picked by hand turns with it.
        cropLandscape = cropLandscape.map { !$0 }
        if aspect != .free { setAspect(aspect) }
    }

    private func resetAll() {
        recipe = EditRecipe()
        aspect = .free
        cropLandscape = nil
    }

    /// Undoes turns, flip, straightening and crop; adjustments stay.
    private func resetGeometry() {
        recipe = EditRecipe(adjustments: recipe.adjustments, look: recipe.look)
        aspect = .free
        cropLandscape = nil
    }

    private var isLandscapeCrop: Bool { cropLandscape ?? (rotatedSize.width >= rotatedSize.height) }
    private var cropRatio: CGFloat? { aspect.ratio(for: rotatedSize, landscape: isLandscapeCrop) }

    private func setAspect(_ option: CropAspect) {
        aspect = option
        guard let ratio = option.ratio(for: rotatedSize, landscape: isLandscapeCrop) else {
            recipe.crop = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        recipe.crop = CropMath.centered(ratio: ratio, imageSize: rotatedSize)
    }

    /// Finds the horizon and straightens it, like Photos' auto.
    private func level() {
        guard let session else { return }
        var unstraightened = recipe
        unstraightened.straighten = 0
        unstraightened.adjustments = Adjustments()
        let image = UncheckedBox(value: unstraightened.apply(to: session.preview, includingCrop: false))
        isLevelling = true
        Task {
            let angle = await Task.detached(priority: .userInitiated) { PhotoEditing.levellingAngle(for: image.value) }.value
            isLevelling = false
            if let angle {
                withAnimation(MetroMotion.standard) { recipe.straighten = angle }
                showCropNote(angle == 0 ? "Already level." : nil)
            } else {
                showCropNote("No horizon found to level.")
            }
        }
    }

    private func showCropNote(_ note: String?) {
        withAnimation(MetroMotion.fade) { cropNote = note }
        guard note != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(MetroMotion.fade) { cropNote = nil }
        }
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
    case crop, light, colour, effects, looks
    var id: String { rawValue }
    /// The adjustments this tab shows on the dial; nil for crop and looks.
    var group: AdjustmentGroup? { AdjustmentGroup(rawValue: rawValue) }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, square, fourThree, threeTwo, sixteenNine, fiveFour, sevenFive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "free"
        case .original: "original"
        case .square: "square"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        case .fiveFour: "5:4"
        case .sevenFive: "7:5"
        }
    }

    /// Long side over short side; nil when the shape is free.
    func longOverShort(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: max(imageSize.width, imageSize.height) / max(min(imageSize.width, imageSize.height), 1)
        case .square: 1
        case .fourThree: 4 / 3
        case .threeTwo: 3 / 2
        case .sixteenNine: 16 / 9
        case .fiveFour: 5 / 4
        case .sevenFive: 7 / 5
        }
    }

    /// Width over height in pixels, wide or tall as asked; nil leaves the crop unconstrained.
    func ratio(for imageSize: CGSize, landscape: Bool) -> CGFloat? {
        longOverShort(for: imageSize).map { landscape ? $0 : 1 / $0 }
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
    let ratio: CGFloat?
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

            // Thirds, for lining things up while cropping and straightening.
            Path { path in
                for third in [1.0 / 3, 2.0 / 3] {
                    path.move(to: CGPoint(x: frame.minX + frame.width * third, y: frame.minY))
                    path.addLine(to: CGPoint(x: frame.minX + frame.width * third, y: frame.maxY))
                    path.move(to: CGPoint(x: frame.minX, y: frame.minY + frame.height * third))
                    path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + frame.height * third))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 0.5)
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
                crop = CropMath.drag(start, corner: corner, to: point, ratio: ratio, imageSize: imageSize)
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
