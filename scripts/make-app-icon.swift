// Draws the "Tile L" app icon (light, dark and tinted) into the app's icon set: a tall tile turning on its left edge
// and a wide tile with hills form an L, with a sun rising in its corner. Matches `LogoMark` in the app and
// `scripts/make-brand.swift`. Run from the repo root: swift scripts/make-app-icon.swift
import AppKit
import CoreGraphics

let side = 1024
let output = "Luminux/Resources/Assets.xcassets/AppIcon.appiconset"

struct Palette {
    let background: CGColor
    let tile: CGColor
    let flapOpacity: CGFloat
    let cutout: CGColor
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let variants: [(String, Palette)] = [
    ("AppIcon.png", Palette(background: rgb(0x0050EF), tile: rgb(0xFFFFFF), flapOpacity: 0.75, cutout: rgb(0x0050EF))),
    ("AppIcon-dark.png", Palette(background: rgb(0x0B0B0B), tile: rgb(0x3D7BFF), flapOpacity: 0.75, cutout: rgb(0x0B0B0B))),
    // Grayscale; the system tints it.
    ("AppIcon-tinted.png", Palette(background: rgb(0x000000), tile: rgb(0xFFFFFF), flapOpacity: 0.7, cutout: rgb(0x000000))),
]

/// Tile L on the same 120-unit grid. The tall tile turns `angle` degrees on its left edge with the app's perspective.
enum TileL {
    static let tall = CGRect(x: 28, y: 26, width: 28, height: 68)
    static let wide = CGRect(x: 60, y: 62, width: 34, height: 32)
    static let angle: CGFloat = 28
    static let depth: CGFloat = 68 / 0.7
    static let sunCorner = CGPoint(x: 60, y: 58)
    static let sunRadius: CGFloat = 22
    static let hills: [CGPoint] = [CGPoint(x: 64, y: 89), CGPoint(x: 71, y: 80), CGPoint(x: 77, y: 85), CGPoint(x: 84, y: 75), CGPoint(x: 90, y: 83)]
    static let hillWidth: CGFloat = 3.4
    static let center = CGPoint(x: 61, y: 60)

    /// A point on the tall tile after turning it on its left edge (the hinge), seen with perspective from its centre line.
    static func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let dx = x - tall.minX, a = angle * .pi / 180
        let w = 1 + dx * sin(a) / depth
        return CGPoint(x: tall.minX + dx * cos(a) / w, y: tall.midY + (y - tall.midY) / w)
    }
}

func drawTileL(_ palette: Palette) -> CGImage {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(side))
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(palette.background)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))

    let unit = CGFloat(side) / 120 * 1.1
    context.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
    context.scaleBy(x: unit, y: unit)
    context.translateBy(x: -TileL.center.x, y: -TileL.center.y)

    // The tall tile, mid-turn and a little see-through so it reads as moving.
    let t = TileL.tall
    let corners = [(t.minX, t.minY), (t.maxX, t.minY), (t.maxX, t.maxY), (t.minX, t.maxY)].map { TileL.project($0.0, $0.1) }
    context.setFillColor(palette.tile.copy(alpha: palette.flapOpacity + 0.1)!)
    context.addLines(between: corners)
    context.closePath()
    context.fillPath()

    // The wide tile with hills cut into it.
    context.setFillColor(palette.tile)
    context.fill(TileL.wide)
    context.setStrokeColor(palette.cutout)
    context.setLineWidth(TileL.hillWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addLines(between: TileL.hills)
    context.strokePath()

    // The quarter sun rising from the L's inner corner.
    let c = TileL.sunCorner, r = TileL.sunRadius
    var sun = [c]
    for i in 0...24 {
        let a = CGFloat(i) / 24 * .pi / 2
        sun.append(CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a)))
    }
    context.setFillColor(palette.tile)
    context.addLines(between: sun)
    context.closePath()
    context.fillPath()
    return context.makeImage()!
}

for (name, palette) in variants {
    let rep = NSBitmapImageRep(cgImage: drawTileL(palette))
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/\(name)"))
    print("wrote \(name)")
}
