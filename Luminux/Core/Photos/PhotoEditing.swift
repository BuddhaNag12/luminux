import CoreImage
import Photos
import UIKit

/// A rotate-and-crop edit. The crop is normalized to the rotated image, with its origin at the top left.
nonisolated struct EditRecipe: Codable, Equatable, Sendable {
    var quarterTurns = 0
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)

    static let formatIdentifier = "com.buddhanag.luminux.edit"
    static let formatVersion = "1"

    var isIdentity: Bool { quarterTurns % 4 == 0 && crop == CGRect(x: 0, y: 0, width: 1, height: 1) }

    /// Rotates counterclockwise by `quarterTurns`, then crops.
    func apply(to image: CIImage) -> CIImage {
        var result = image
        for _ in 0..<((quarterTurns % 4 + 4) % 4) {
            result = result.oriented(.left)
        }
        let extent = result.extent
        let rect = CGRect(
            x: extent.minX + crop.minX * extent.width,
            y: extent.minY + (1 - crop.maxY) * extent.height,
            width: crop.width * extent.width,
            height: crop.height * extent.height
        ).integral
        return result.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }
}

nonisolated enum PhotoEditing {
    static let context = CIContext()

    /// Renders an edited preview for the editor screen.
    static func preview(of image: UIImage, quarterTurns: Int) -> UIImage? {
        guard let input = CIImage(image: image, options: [.applyOrientationProperty: true]) else { return nil }
        let recipe = EditRecipe(quarterTurns: quarterTurns)
        let output = recipe.apply(to: input)
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Renders the full-size edit into the editing output's JPEG file.
    static func render(_ recipe: EditRecipe, from url: URL, to output: URL) throws {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw EditError.unreadableImage
        }
        let edited = recipe.apply(to: input)
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

extension PHAsset {
    /// Rotate and crop work on still photos; Live Photos and videos need their own pipelines.
    var supportsLuminuxEdits: Bool {
        mediaType == .image && !mediaSubtypes.contains(.photoLive) && canPerform(.content)
    }
}

extension PhotoLibrary {
    func applyEdit(_ recipe: EditRecipe, to asset: PHAsset) async throws {
        let input = try await contentEditingInput(for: asset)
        guard let sourceURL = input.value.fullSizeImageURL else { throw PhotoEditing.EditError.unreadableImage }

        let output = PHContentEditingOutput(contentEditingInput: input.value)
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: EditRecipe.formatIdentifier,
            formatVersion: EditRecipe.formatVersion,
            data: try JSONEncoder().encode(recipe)
        )
        let destination = output.renderedContentURL
        try await Task.detached(priority: .userInitiated) {
            try PhotoEditing.render(recipe, from: sourceURL, to: destination)
        }.value

        let change = UncheckedBox(value: (asset, output))
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

    private func contentEditingInput(for asset: PHAsset) async throws -> UncheckedBox<PHContentEditingInput> {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        // Edits apply on top of the current version, so earlier edits never need replaying.
        options.canHandleAdjustmentData = { @Sendable _ in false }
        let input: UncheckedBox<PHContentEditingInput>? = await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { @Sendable input, _ in
                continuation.resume(returning: input.map(UncheckedBox.init))
            }
        }
        guard let input else { throw PhotoEditing.EditError.noEditingInput }
        return input
    }
}
