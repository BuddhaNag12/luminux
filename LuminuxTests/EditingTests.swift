import CoreGraphics
import CoreImage
import Testing
@testable import Luminux

struct CropMathTests {
    private let landscape = CGSize(width: 4000, height: 3000)

    @Test func squareOnLandscapeTrimsTheSides() {
        let crop = CropMath.centered(ratio: 1, imageSize: landscape)
        #expect(crop.height == 1)
        #expect(abs(crop.width - 0.75) < 0.0001)
        #expect(abs(crop.midX - 0.5) < 0.0001)
    }

    @Test func wideOnLandscapeTrimsTopAndBottom() {
        let crop = CropMath.centered(ratio: 16 / 9, imageSize: landscape)
        #expect(crop.width == 1)
        #expect(crop.height < 1)
        #expect(abs(crop.midY - 0.5) < 0.0001)
    }

    @Test func freeDragMovesOnlyTheDraggedCorner() {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let crop = CropMath.drag(full, corner: .topLeading, to: CGPoint(x: 0.2, y: 0.3), ratio: nil, imageSize: landscape)
        #expect(abs(crop.minX - 0.2) < 0.0001)
        #expect(abs(crop.minY - 0.3) < 0.0001)
        #expect(crop.maxX == 1)
        #expect(crop.maxY == 1)
    }

    @Test func dragKeepsAMinimumSize() {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let crop = CropMath.drag(full, corner: .bottomTrailing, to: CGPoint(x: -1, y: -1), ratio: nil, imageSize: landscape)
        #expect(crop.width >= CropMath.minimumSide - 0.0001)
        #expect(crop.height >= CropMath.minimumSide - 0.0001)
    }

    @Test func lockedDragKeepsThePixelRatio() {
        let start = CropMath.centered(ratio: 1, imageSize: landscape)
        let crop = CropMath.drag(start, corner: .bottomTrailing, to: CGPoint(x: 0.7, y: 0.9), ratio: 1, imageSize: landscape)
        let pixelRatio = (crop.width * landscape.width) / (crop.height * landscape.height)
        #expect(abs(pixelRatio - 1) < 0.001)
    }

    @Test func moveStaysInsideTheImage() {
        let crop = CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4)
        let moved = CropMath.move(crop, by: CGSize(width: 0.5, height: -0.9))
        #expect(moved.maxX <= 1)
        #expect(moved.minY >= 0)
        #expect(moved.size == crop.size)
    }
}

struct EditRecipeTests {
    private let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))

    @Test func identityRecipeKeepsTheSize() {
        let output = EditRecipe().apply(to: image)
        #expect(output.extent.size == CGSize(width: 400, height: 300))
        #expect(EditRecipe().isIdentity)
    }

    @Test func quarterTurnSwapsWidthAndHeight() {
        let output = EditRecipe(quarterTurns: 1).apply(to: image)
        #expect(output.extent.size == CGSize(width: 300, height: 400))
    }

    @Test func cropUsesTopLeftOriginAndStartsAtZero() {
        let recipe = EditRecipe(quarterTurns: 0, crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        let output = recipe.apply(to: image)
        #expect(output.extent == CGRect(x: 0, y: 0, width: 200, height: 150))
    }

    @Test func fullTurnIsIdentity() {
        #expect(EditRecipe(quarterTurns: 4).isIdentity)
    }
}

struct AdjustmentTests {
    private let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    private let warmish = CIImage(color: CIColor(red: 0.7, green: 0.4, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

    private func pixel(_ image: CIImage) -> [Int] {
        var bytes = [UInt8](repeating: 0, count: 4)
        PhotoEditing.context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 4, y: 4, width: 1, height: 1),
                                    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return bytes.prefix(3).map(Int.init)
    }

    @Test func versionOneRecipesStillOpen() throws {
        let json = #"{"quarterTurns":1,"crop":[[0,0],[1,1]]}"#.data(using: .utf8)!
        let recipe = try JSONDecoder().decode(EditRecipe.self, from: json)
        #expect(recipe.quarterTurns == 1)
        #expect(recipe.adjustments.isNeutral)
        #expect(recipe.look == nil)
    }

    @Test func recipesRoundTripWithTheirLook() throws {
        for look in Look.allCases {
            let recipe = EditRecipe(quarterTurns: 2, adjustments: look.adjustments, look: look)
            let decoded = try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(recipe))
            #expect(decoded == recipe)
        }
    }

    @Test func neutralAdjustmentsLeaveThePixelsAlone() {
        #expect(pixel(Adjustments().apply(to: warmish)) == pixel(warmish))
        #expect(EditRecipe().isIdentity)
        #expect(!EditRecipe(adjustments: Adjustments([.exposure: 0.2])).isIdentity)
    }

    @Test func exposureBrightens() {
        let brighter = pixel(Adjustments([.exposure: 0.5]).apply(to: gray))
        #expect(brighter[0] > pixel(gray)[0] + 20)
    }

    @Test func warmthAddsRedOverBlue() {
        let warm = pixel(Adjustments([.temperature: 0.5]).apply(to: gray))
        #expect(warm[0] > warm[2] + 10)
        let cool = pixel(Adjustments([.temperature: -0.5]).apply(to: gray))
        #expect(cool[2] > cool[0] + 10)
    }

    @Test func noSaturationIsGray() {
        let mono = pixel(Adjustments([.saturation: -1]).apply(to: warmish))
        #expect(abs(mono[0] - mono[1]) <= 1 && abs(mono[1] - mono[2]) <= 1)
    }

    @Test func slidersClampAndClearAtZero() {
        var adjustments = Adjustments()
        adjustments[.vignette] = -0.5
        #expect(adjustments[.vignette] == 0)
        #expect(adjustments.isNeutral)
        adjustments[.exposure] = 3
        #expect(adjustments[.exposure] == 1)
    }

    @Test func adjustmentsKeepThePhotoSize() {
        let all = Adjustments(Dictionary(uniqueKeysWithValues: Adjustment.allCases.map { ($0, 0.5) }))
        #expect(all.apply(to: warmish).extent == warmish.extent)
    }

    @Test func rotatingKeepsTheSameCroppedArea() {
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let recipe = EditRecipe(crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        let turned = recipe.rotatedLeft()
        #expect(turned.quarterTurns == 1)
        // The top-right quarter of the photo lands in the top-left after a counterclockwise turn.
        #expect(turned.crop == CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(turned.apply(to: image).extent.size == CGSize(width: 150, height: 200))
    }
}

struct EditorControlTests {
    @Test func everyAdjustmentIsInOneGroup() {
        let grouped = AdjustmentGroup.allCases.flatMap(\.adjustments)
        #expect(grouped.count == Adjustment.allCases.count)
        #expect(Set(grouped) == Set(Adjustment.allCases))
        #expect(AdjustmentGroup.allCases == [.light, .colour, .effects])
    }

    @Test func theDialFollowsTheDragAndCatchesZero() {
        let full = MetroDial.pointsPerRange
        // Dragging left raises the value; half the drag distance covers half the range.
        #expect(abs(MetroDial.value(from: 0, dragged: -full / 4, range: -1...1, resting: 0) - 0.5) < 0.0001)
        // Clamped at the ends.
        #expect(MetroDial.value(from: 0.9, dragged: -full, range: -1...1, resting: 0) == 1)
        #expect(MetroDial.value(from: 0.5, dragged: full, range: 0...1, resting: 0) == 0)
        // Caught at zero only when close to it.
        #expect(MetroDial.value(from: 0, dragged: -full * 0.01, range: -1...1, resting: 0) == 0)
        #expect(MetroDial.value(from: 0, dragged: -full * 0.05, range: -1...1, resting: 0) != 0)
        #expect(MetroDial.text(for: 0.24) == "+24")
        #expect(MetroDial.text(for: -0.07) == "-7")
    }
}

struct StraightenAndFlipTests {
    @Test func straighteningZoomsJustEnoughToCover() {
        #expect(EditRecipe.straightenScale(degrees: 0, size: CGSize(width: 4, height: 3)) == 1)
        let scale = EditRecipe.straightenScale(degrees: 10, size: CGSize(width: 400, height: 300))
        // The frame's corners, turned back by the angle, land inside the zoomed photo.
        let angle = 10 * Double.pi / 180
        let halfWidth = 200 * cos(angle) + 150 * sin(angle)
        let halfHeight = 200 * sin(angle) + 150 * cos(angle)
        #expect(halfWidth <= 200 * scale + 0.001 && halfHeight <= 150 * scale + 0.001)
        #expect(scale < 1.4)
    }

    @Test func aStraightenedPhotoKeepsItsSizeAndHasNoEmptyCorner() {
        let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))
        let output = EditRecipe(straighten: 15).apply(to: red)
        #expect(output.extent.size == CGSize(width: 120, height: 80))
        var pixel = [UInt8](repeating: 0, count: 4)
        PhotoEditing.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        #expect(pixel[3] == 255)
        #expect(pixel[0] > 200)
    }

    @Test func flippingTwiceIsNoChangeAndMirrorsTheCrop() {
        let recipe = EditRecipe(quarterTurns: 1, straighten: 7, crop: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        let flipped = recipe.flippedHorizontally()
        #expect(flipped.flipped)
        #expect(flipped.straighten == -7)
        #expect(abs(flipped.crop.minX - 0.6) < 0.0001)
        let back = flipped.flippedHorizontally()
        #expect(!back.flipped && back.straighten == 7 && back.quarterTurns == 1)
        #expect(abs(back.crop.minX - 0.1) < 0.0001 && abs(back.crop.width - 0.3) < 0.0001)
        #expect(!flipped.hasNoGeometry)
    }

    @Test func aMirroredPhotoStillTurnsLeft() {
        // Turning left after a flip must look the same as flipping after turning right three times over.
        let image = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20))
        let flippedThenLeft = EditRecipe().flippedHorizontally().rotatedLeft().apply(to: image)
        #expect(flippedThenLeft.extent.size == CGSize(width: 20, height: 40))
        #expect(EditRecipe().flippedHorizontally().rotatedLeft().quarterTurns == 3)
    }

    @Test func olderRecipesStillOpen() throws {
        let old = #"{"quarterTurns":1,"crop":[[0,0],[1,1]]}"#.data(using: .utf8)!
        let recipe = try JSONDecoder().decode(EditRecipe.self, from: old)
        #expect(recipe.quarterTurns == 1 && !recipe.flipped && recipe.straighten == 0)
    }

    @Test func autoLevelsATiltedHorizon() throws {
        // Sky over sea, then tilted 8° clockwise by straightening; levelling should turn it back.
        let size = CGRect(x: 0, y: 0, width: 600, height: 400)
        let sky = CIImage(color: CIColor(red: 0.5, green: 0.7, blue: 1)).cropped(to: CGRect(x: 0, y: 200, width: 600, height: 200))
        let sea = CIImage(color: CIColor(red: 0.05, green: 0.2, blue: 0.35)).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 200))
        let scene = sky.composited(over: sea).cropped(to: size)
        let tilted = EditRecipe(straighten: 8).apply(to: scene)
        let angle = try #require(PhotoEditing.levellingAngle(for: tilted))
        #expect(abs(angle + 8) < 2, "levelling angle \(angle)")
    }
}

struct CropAspectTests {
    @Test func shapesTurnWithTheirOrientation() {
        let wide = CGSize(width: 4000, height: 3000)
        func ratio(_ aspect: CropAspect, _ size: CGSize, landscape: Bool) -> Double { Double(aspect.ratio(for: size, landscape: landscape) ?? -1) }
        #expect(CropAspect.free.ratio(for: wide, landscape: true) == nil)
        #expect(ratio(.square, wide, landscape: false) == 1)
        #expect(abs(ratio(.sixteenNine, wide, landscape: true) - 16.0 / 9) < 0.0001)
        #expect(abs(ratio(.sixteenNine, wide, landscape: false) - 9.0 / 16) < 0.0001)
        // The photo's own shape, either way round.
        #expect(abs(ratio(.original, wide, landscape: true) - 4.0 / 3) < 0.0001)
        #expect(abs(ratio(.original, CGSize(width: 3000, height: 4000), landscape: false) - 3.0 / 4) < 0.0001)
    }

    @Test func degreesReadCleanly() {
        #expect(MetroDial.degrees(0) == "0°")
        #expect(MetroDial.degrees(12) == "+12°")
        #expect(MetroDial.degrees(-3.46) == "-3.5°")
        // The straighten ruler catches level within a degree or so.
        #expect(MetroDial.value(from: 0, dragged: -4, range: -45...45, resting: 0) == 0)
    }
}
