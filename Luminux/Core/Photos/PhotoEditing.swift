import CoreImage
import ImageIO
import Photos
import UIKit

/// A rotate, crop and adjust edit. The crop is normalized to the rotated image, with its origin at the top left.
/// Saved with the photo, so the editor can reopen it and rebuild from the original.
nonisolated struct EditRecipe: Codable, Equatable, Sendable {
    var quarterTurns = 0
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var adjustments = Adjustments()
    /// The preset the adjustments came from, for highlighting it; the adjustments alone decide the result.
    var look: Look?

    static let formatIdentifier = "com.buddhanag.luminux.edit"
    static let formatVersion = "2"
    /// Versions this build can reopen. Version 1 had rotate and crop only.
    static let readableVersions: Set<String> = ["1", "2"]

    init(quarterTurns: Int = 0, crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), adjustments: Adjustments = Adjustments(), look: Look? = nil) {
        self.quarterTurns = quarterTurns
        self.crop = crop
        self.adjustments = adjustments
        self.look = look
    }

    private enum CodingKeys: String, CodingKey { case quarterTurns, crop, adjustments, look }

    /// Fields a recipe was saved without keep their defaults, so older edits still open.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quarterTurns = try container.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0
        crop = try container.decodeIfPresent(CGRect.self, forKey: .crop) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        adjustments = try container.decodeIfPresent(Adjustments.self, forKey: .adjustments) ?? Adjustments()
        look = try? container.decodeIfPresent(Look.self, forKey: .look)
    }

    var isIdentity: Bool { hasNoGeometry && adjustments.isNeutral }
    var hasNoGeometry: Bool { quarterTurns % 4 == 0 && crop == CGRect(x: 0, y: 0, width: 1, height: 1) }

    /// One more quarter turn counterclockwise, with the crop turned along so it keeps framing the same part.
    func rotatedLeft() -> EditRecipe {
        var next = self
        next.quarterTurns = (quarterTurns + 1) % 4
        // A point at (x, y) from the top left lands at (y, 1 - x) after a counterclockwise turn.
        next.crop = CGRect(x: crop.minY, y: 1 - crop.maxX, width: crop.height, height: crop.width)
        return next
    }

    /// Rotates counterclockwise by `quarterTurns`, crops, then adjusts.
    func apply(to image: CIImage, includingCrop: Bool = true) -> CIImage {
        var result = image
        for _ in 0..<((quarterTurns % 4 + 4) % 4) {
            result = result.oriented(.left)
        }
        if includingCrop {
            let extent = result.extent
            let rect = CGRect(
                x: extent.minX + crop.minX * extent.width,
                y: extent.minY + (1 - crop.maxY) * extent.height,
                width: crop.width * extent.width,
                height: crop.height * extent.height
            ).integral
            result = result.cropped(to: rect)
        }
        result = result.transformed(by: CGAffineTransform(translationX: -result.extent.minX, y: -result.extent.minY))
        return adjustments.apply(to: result)
    }
}

/// One slider in the editor.
nonisolated enum Adjustment: String, CaseIterable, Identifiable, Sendable {
    case exposure, brightness, contrast, highlights, shadows
    case temperature, tint, saturation, vibrance
    case sharpness, vignette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: "warmth"
        default: rawValue
        }
    }

    /// Sharpness and vignette only add; everything else goes both ways from zero.
    var range: ClosedRange<Double> {
        switch self {
        case .sharpness, .vignette: 0...1
        default: -1...1
        }
    }
}

/// Slider values, each 0 when untouched. Stored by name, so recipes from other versions still decode.
nonisolated struct Adjustments: Codable, Equatable, Sendable {
    private var values: [String: Double] = [:]

    init() {}

    init(_ values: [Adjustment: Double]) {
        for (adjustment, value) in values { self[adjustment] = value }
    }

    subscript(_ adjustment: Adjustment) -> Double {
        get { values[adjustment.rawValue] ?? 0 }
        set {
            let clamped = min(max(newValue, adjustment.range.lowerBound), adjustment.range.upperBound)
            values[adjustment.rawValue] = clamped == 0 ? nil : clamped
        }
    }

    var isNeutral: Bool { values.isEmpty }

    /// Untouched sliders skip their filter, so a neutral recipe leaves the pixels alone.
    func apply(to image: CIImage) -> CIImage {
        guard !isNeutral else { return image }
        let extent = image.extent
        var result = image

        if self[.exposure] != 0 {
            result = result.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: self[.exposure] * 2])
        }
        if self[.temperature] != 0 || self[.tint] != 0 {
            // A lower target white point warms the picture; a positive target tint turns it green.
            result = result.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 - self[.temperature] * 2000, y: -self[.tint] * 50),
            ])
        }
        if self[.brightness] != 0 || self[.contrast] != 0 || self[.saturation] != 0 {
            result = result.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: self[.brightness] * 0.25,
                kCIInputContrastKey: 1 + self[.contrast] * 0.5,
                kCIInputSaturationKey: 1 + self[.saturation],
            ])
        }
        if self[.vibrance] != 0 {
            result = result.applyingFilter("CIVibrance", parameters: [kCIInputAmountKey: self[.vibrance]])
        }
        if self[.highlights] != 0 {
            // Bends the bright end of the tone curve; the darker half stays where it is.
            let lift = self[.highlights]
            result = result.applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 0.25, y: 0.25),
                "inputPoint2": CIVector(x: 0.5, y: 0.5),
                "inputPoint3": CIVector(x: 0.75, y: 0.75 + lift * 0.15),
                "inputPoint4": CIVector(x: 1, y: 1 + min(lift, 0) * 0.12),
            ])
        }
        if self[.shadows] != 0 {
            result = result.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputShadowAmount": self[.shadows],
                "inputHighlightAmount": 1,
            ])
        }
        if self[.sharpness] != 0 {
            result = result.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: self[.sharpness] * 0.8])
        }
        if self[.vignette] != 0 {
            result = result.applyingFilter("CIVignetteEffect", parameters: [
                kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                kCIInputRadiusKey: hypot(extent.width, extent.height) / 2 * 0.65,
                kCIInputIntensityKey: self[.vignette],
                "inputFalloff": 0.6,
            ])
        }
        // Some filters reach past the edges; the photo keeps its size.
        return result.cropped(to: extent)
    }
}

/// One-tap starting points; each is just a set of slider values.
nonisolated enum Look: String, CaseIterable, Codable, Identifiable, Sendable {
    case vivid, warm, cool, mono, noir, fade

    var id: String { rawValue }

    var adjustments: Adjustments {
        switch self {
        case .vivid: Adjustments([.saturation: 0.25, .vibrance: 0.4, .contrast: 0.15])
        case .warm: Adjustments([.temperature: 0.45, .vibrance: 0.1])
        case .cool: Adjustments([.temperature: -0.45, .tint: -0.05])
        case .mono: Adjustments([.saturation: -1, .contrast: 0.1])
        case .noir: Adjustments([.saturation: -1, .contrast: 0.5, .exposure: -0.1, .vignette: 0.5])
        case .fade: Adjustments([.contrast: -0.3, .saturation: -0.2, .shadows: 0.3, .brightness: 0.1])
        }
    }
}

nonisolated enum PhotoEditing {
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// Renders an edit for the editor's screen.
    static func preview(of image: CIImage, recipe: EditRecipe, includingCrop: Bool) -> UIImage? {
        let output = recipe.apply(to: image, includingCrop: includingCrop)
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// The photo at screen size with its orientation applied, decoded once for the editor's previews.
    static func previewSource(from url: URL, maxPixelSize: Int = 2048) -> CIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return CIImage(cgImage: thumbnail)
    }

    /// Renders the full-size edit into the editing output's JPEG file, keeping the original's metadata.
    static func render(_ recipe: EditRecipe, from url: URL, to output: URL) throws {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw EditError.unreadableImage
        }
        // The pixels are upright now, so the saved file must not ask for another turn.
        var properties = input.properties
        properties[kCGImagePropertyOrientation as String] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            properties[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        let edited = recipe.apply(to: input).settingProperties(properties)
        let colorSpace = input.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        try context.writeJPEGRepresentation(
            of: edited,
            to: output,
            colorSpace: colorSpace,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.93]
        )
    }

    enum EditError: Error {
        case unreadableImage, noEditingInput
    }
}

/// An open edit: the photo as it was before Luminux's last edit, and that edit, so it can be changed rather than
/// stacked on top of.
nonisolated struct EditSession: @unchecked Sendable {
    let asset: PHAsset
    let input: PHContentEditingInput
    let sourceURL: URL
    let recipe: EditRecipe
    let preview: CIImage
}

extension PHAsset {
    /// Rotate and crop work on still photos; Live Photos and videos need their own pipelines.
    var supportsLuminuxEdits: Bool {
        mediaType == .image && !mediaSubtypes.contains(.photoLive) && canPerform(.content)
    }
}

extension PhotoLibrary {
    /// Opens the photo for editing, with Luminux's last edit undone and handed back for the sliders.
    func editSession(for asset: PHAsset) async throws -> EditSession {
        let input = try await contentEditingInput(for: asset)
        guard let sourceURL = input.value.fullSizeImageURL else { throw PhotoEditing.EditError.unreadableImage }
        let recipe = input.value.adjustmentData.flatMap(Self.recipe(from:)) ?? EditRecipe()
        let preview = try await Task.detached(priority: .userInitiated) {
            guard let image = PhotoEditing.previewSource(from: sourceURL) else { throw PhotoEditing.EditError.unreadableImage }
            return UncheckedBox(value: image)
        }.value.value
        return EditSession(asset: asset, input: input.value, sourceURL: sourceURL, recipe: recipe, preview: preview)
    }

    /// A quarter turn on top of the photo's current Luminux edit, without opening the editor.
    func rotateLeft(_ asset: PHAsset) async throws {
        let session = try await editSession(for: asset)
        try await applyEdit(session.recipe.rotatedLeft(), in: session)
    }

    /// Saves `recipe` in place of the session's earlier edit, rendered from the original.
    func applyEdit(_ recipe: EditRecipe, in session: EditSession) async throws {
        let output = PHContentEditingOutput(contentEditingInput: session.input)
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: EditRecipe.formatIdentifier,
            formatVersion: EditRecipe.formatVersion,
            data: try JSONEncoder().encode(recipe)
        )
        let source = session.sourceURL
        let destination = output.renderedContentURL
        try await Task.detached(priority: .userInitiated) {
            try PhotoEditing.render(recipe, from: source, to: destination)
        }.value

        let change = UncheckedBox(value: (session.asset, output))
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest(for: change.value.0).contentEditingOutput = change.value.1
        }
    }

    func revertEdits(_ asset: PHAsset) async throws {
        let box = UncheckedBox(value: asset)
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest(for: box.value).revertAssetContentToOriginal()
        }
    }

    static func recipe(from data: PHAdjustmentData) -> EditRecipe? {
        guard data.formatIdentifier == EditRecipe.formatIdentifier, EditRecipe.readableVersions.contains(data.formatVersion) else { return nil }
        return try? JSONDecoder().decode(EditRecipe.self, from: data.data)
    }

    private func contentEditingInput(for asset: PHAsset) async throws -> UncheckedBox<PHContentEditingInput> {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        // Luminux's own edits are reopened from the original; anything else is edited on top of.
        options.canHandleAdjustmentData = { @Sendable data in
            data.formatIdentifier == EditRecipe.formatIdentifier && EditRecipe.readableVersions.contains(data.formatVersion)
        }
        let input: UncheckedBox<PHContentEditingInput>? = await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { @Sendable input, _ in
                continuation.resume(returning: input.map(UncheckedBox.init))
            }
        }
        guard let input else { throw PhotoEditing.EditError.noEditingInput }
        return input
    }
}
