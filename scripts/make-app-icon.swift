// Draws the tile-stack app icon (light, dark and tinted) into the app's icon set.
// Run from the repo root: swift scripts/make-app-icon.swift
import AppKit
import CoreGraphics

let side = 1024
let output = "Luminux/Resources/Assets.xcassets/AppIcon.appiconset"

struct Palette {
    let background: CGColor
    /// Back to front.
    let tiles: [CGColor]
    let detail: CGColor
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let variants: [(String, Palette)] = [
    ("AppIcon.png", Palette(background: rgb(0x0050EF), tiles: [rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0.7), rgb(0xFFFFFF)], detail: rgb(0x0050EF))),
    ("AppIcon-dark.png", Palette(background: rgb(0x0B0B0B), tiles: [rgb(0x2F6BFF, 0.45), rgb(0x2F6BFF, 0.7), rgb(0x3D7BFF)], detail: rgb(0x0B0B0B))),
    // Grayscale; the system tints it.
    ("AppIcon-tinted.png", Palette(background: rgb(0x000000), tiles: [rgb(0xFFFFFF, 0.4), rgb(0xFFFFFF, 0.65), rgb(0xFFFFFF)], detail: rgb(0x000000))),
]

/// The glyph is laid out on a 120-unit tile (the concept sketch), then scaled up around the centre.
let unit = CGFloat(side) / 120
let glyphScale: CGFloat = 1.18

func draw(_ palette: Palette) -> CGImage {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Flip to a top-left origin like the sketch.
    context.translateBy(x: 0, y: CGFloat(side))
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(palette.background)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))

    context.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
    context.scaleBy(x: unit * glyphScale, y: unit * glyphScale)
    context.translateBy(x: -59, y: -59)

    let tiles = [CGRect(x: 46, y: 24, width: 46, height: 46), CGRect(x: 36, y: 36, width: 46, height: 46), CGRect(x: 26, y: 48, width: 46, height: 46)]
    for (rect, color) in zip(tiles, palette.tiles) {
        context.setFillColor(color)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.fillPath()
    }

    context.setFillColor(palette.detail)
    context.fillEllipse(in: CGRect(x: 58 - 5, y: 62 - 5, width: 10, height: 10))
    context.setStrokeColor(palette.detail)
    context.setLineWidth(4)
    context.setLineJoin(.round)
    context.setLineCap(.round)
    context.addLines(between: [CGPoint(x: 30, y: 88), CGPoint(x: 44, y: 74), CGPoint(x: 52, y: 82), CGPoint(x: 60, y: 76), CGPoint(x: 68, y: 88)])
    context.strokePath()
    return context.makeImage()!
}

for (name, palette) in variants {
    let rep = NSBitmapImageRep(cgImage: draw(palette))
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/\(name)"))
    print("wrote \(name)")
}
