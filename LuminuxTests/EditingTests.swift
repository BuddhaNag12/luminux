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
