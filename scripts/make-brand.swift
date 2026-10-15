// Draws the Luminux brand set from the "Tile L" mark into docs/brand: the icon and the logo lockups (mark plus
// "luminux" in Selawik Light, the app's font), each as an SVG with the text outlined and a 2x PNG.
// The mark's geometry is the same 120-unit grid as `scripts/make-app-icon.swift` (`TileL`) and `LogoMark` in the app.
// Run from the repo root: swift scripts/make-brand.swift
import AppKit
import CoreGraphics
import CoreText

let outputDir = "docs/brand"
let fontURL = URL(fileURLWithPath: "Luminux/Resources/Fonts/selawkl.ttf")

// MARK: Mark geometry (keep in step with the icon script)

enum TileL {
    static let tall = CGRect(x: 28, y: 26, width: 28, height: 68)
    static let wide = CGRect(x: 60, y: 62, width: 34, height: 32)
    static let angle: CGFloat = 28
    static let depth: CGFloat = 68 / 0.7
    static let sunCorner = CGPoint(x: 60, y: 58)
    static let sunRadius: CGFloat = 22
    static let hills: [CGPoint] = [CGPoint(x: 64, y: 89), CGPoint(x: 71, y: 80), CGPoint(x: 77, y: 85), CGPoint(x: 84, y: 75), CGPoint(x: 90, y: 83)]
    static let hillWidth: CGFloat = 3.4
    /// The mark's bounds on the grid.
    static let bounds = CGRect(x: 28, y: 26, width: 66, height: 68)

    static func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let dx = x - tall.minX, a = angle * .pi / 180
        let w = 1 + dx * sin(a) / depth
        return CGPoint(x: tall.minX + dx * cos(a) / w, y: tall.midY + (y - tall.midY) / w)
    }

    static var tallCorners: [CGPoint] {
        [(tall.minX, tall.minY), (tall.maxX, tall.minY), (tall.maxX, tall.maxY), (tall.minX, tall.maxY)].map { project($0.0, $0.1) }
    }

    static var sun: [CGPoint] {
        var points = [sunCorner]
        for i in 0...24 {
            let a = CGFloat(i) / 24 * .pi / 2
            points.append(CGPoint(x: sunCorner.x + sunRadius * sin(a), y: sunCorner.y - sunRadius * cos(a)))
        }
        return points
    }
}

// MARK: Drawing model

struct Colors {
    let background: UInt32?
    let tile: UInt32
    let tallOpacity: CGFloat
    let ink: UInt32
}

enum Layout { case icon, horizontal, stacked }

struct Variant {
    let name: String
    let layout: Layout
    let colors: Colors
}

let cobalt: UInt32 = 0x0050EF, white: UInt32 = 0xFFFFFF, black: UInt32 = 0x000000, ink: UInt32 = 0x111111, darkTile: UInt32 = 0x3D7BFF

let variants = [
    Variant(name: "luminux-icon", layout: .icon, colors: Colors(background: cobalt, tile: white, tallOpacity: 0.85, ink: white)),
    Variant(name: "luminux-lockup-horizontal", layout: .horizontal, colors: Colors(background: white, tile: cobalt, tallOpacity: 0.8, ink: ink)),
    Variant(name: "luminux-lockup-horizontal-dark", layout: .horizontal, colors: Colors(background: black, tile: darkTile, tallOpacity: 0.8, ink: white)),
    Variant(name: "luminux-lockup-stacked", layout: .stacked, colors: Colors(background: white, tile: cobalt, tallOpacity: 0.8, ink: ink)),
    Variant(name: "luminux-lockup-mono-white", layout: .horizontal, colors: Colors(background: cobalt, tile: white, tallOpacity: 0.85, ink: white)),
    Variant(name: "luminux-lockup-mono-black", layout: .stacked, colors: Colors(background: white, tile: black, tallOpacity: 0.8, ink: black)),
]

/// Where the mark and the word go on the canvas.
struct Placement {
    let size: CGSize
    /// Canvas points per grid unit, and the canvas point of the mark's top-left corner.
    let unit: CGFloat
    let markOrigin: CGPoint
    let fontSize: CGFloat
    /// Left end of the word's baseline; nil for the icon.
    let baseline: CGPoint?
}

let font = { () -> CTFont in
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor], let first = descriptors.first else {
        fatalError("Can't read \(fontURL.path); run from the repo root.")
    }
    return CTFontCreateWithFontDescriptor(first, 100, nil)
}()

/// "luminux" as one outline path at the given size, with its baseline at y = 0 and y growing downward.
func wordPath(size: CGFloat) -> (path: CGPath, width: CGFloat, xHeight: CGFloat, ascender: CGFloat) {
    let sized = CTFontCreateCopyWithAttributes(font, size, nil, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "luminux", attributes: [.font: sized]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for (glyph, position) in zip(glyphs, positions) {
            guard let outline = CTFontCreatePathForGlyph(sized, glyph, nil) else { continue }
            // Glyph outlines are y-up; flip into the canvas's y-down space.
            path.addPath(outline, transform: CGAffineTransform(translationX: position.x, y: 0).scaledBy(x: 1, y: -1))
        }
    }
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    return (path, width, CTFontGetXHeight(sized), CTFontGetAscent(sized))
}

func placement(for layout: Layout) -> Placement {
    switch layout {
    case .icon:
        let side: CGFloat = 1024, unit = side / 120 * 1.1
        let origin = CGPoint(x: side / 2 + (TileL.bounds.minX - 61) * unit, y: side / 2 + (TileL.bounds.minY - 60) * unit)
        return Placement(size: CGSize(width: side, height: side), unit: unit, markOrigin: origin, fontSize: 0, baseline: nil)
    case .horizontal:
        let size = CGSize(width: 1300, height: 480), markHeight: CGFloat = 280, unit = markHeight / TileL.bounds.height
        let fontSize: CGFloat = 200
        let word = wordPath(size: fontSize)
        let gap: CGFloat = 64
        let total = TileL.bounds.width * unit + gap + word.width
        let left = (size.width - total) / 2
        let markTop = (size.height - markHeight) / 2
        // The word's ascender line meets the top of the mark, its baseline the bottom.
        let baseline = CGPoint(x: left + TileL.bounds.width * unit + gap, y: markTop + markHeight - 4)
        return Placement(size: size, unit: unit, markOrigin: CGPoint(x: left, y: markTop), fontSize: fontSize, baseline: baseline)
    case .stacked:
        let size = CGSize(width: 820, height: 820), markHeight: CGFloat = 340, unit = markHeight / TileL.bounds.height
        let fontSize: CGFloat = 170
        let word = wordPath(size: fontSize)
        let markLeft = (size.width - TileL.bounds.width * unit) / 2
        return Placement(size: size, unit: unit, markOrigin: CGPoint(x: markLeft, y: 120), fontSize: fontSize,
                         baseline: CGPoint(x: (size.width - word.width) / 2, y: 120 + markHeight + 60 + word.ascender * 0.78))
    }
}

/// Grid point to canvas point.
func canvas(_ p: CGPoint, _ place: Placement) -> CGPoint {
    CGPoint(x: place.markOrigin.x + (p.x - TileL.bounds.minX) * place.unit, y: place.markOrigin.y + (p.y - TileL.bounds.minY) * place.unit)
}

// MARK: SVG

func hex(_ value: UInt32) -> String { String(format: "#%06X", value) }

func svgPath(_ points: [CGPoint], close: Bool) -> String {
    "M " + points.map { String(format: "%.2f %.2f", $0.x, $0.y) }.joined(separator: " L ") + (close ? " Z" : "")
}

func svgPath(_ path: CGPath) -> String {
    var parts: [String] = []
    path.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: parts.append(String(format: "M%.2f %.2f", p[0].x, p[0].y))
        case .addLineToPoint: parts.append(String(format: "L%.2f %.2f", p[0].x, p[0].y))
        case .addQuadCurveToPoint: parts.append(String(format: "Q%.2f %.2f %.2f %.2f", p[0].x, p[0].y, p[1].x, p[1].y))
        case .addCurveToPoint: parts.append(String(format: "C%.2f %.2f %.2f %.2f %.2f %.2f", p[0].x, p[0].y, p[1].x, p[1].y, p[2].x, p[2].y))
        case .closeSubpath: parts.append("Z")
        @unknown default: break
        }
    }
    return parts.joined()
}

func svg(_ variant: Variant) -> String {
    let place = placement(for: variant.layout), c = variant.colors
    let cutout = c.background ?? 0xFFFFFF
    var body: [String] = []
    if let background = c.background {
        body.append("<rect width=\"\(Int(place.size.width))\" height=\"\(Int(place.size.height))\" fill=\"\(hex(background))\"/>")
    }
    body.append("<path d=\"\(svgPath(TileL.tallCorners.map { canvas($0, place) }, close: true))\" fill=\"\(hex(c.tile))\" fill-opacity=\"\(c.tallOpacity)\"/>")
    let wide = TileL.wide
    body.append("<path d=\"\(svgPath([wide.origin, CGPoint(x: wide.maxX, y: wide.minY), CGPoint(x: wide.maxX, y: wide.maxY), CGPoint(x: wide.minX, y: wide.maxY)].map { canvas($0, place) }, close: true))\" fill=\"\(hex(c.tile))\"/>")
    body.append("<path d=\"\(svgPath(TileL.hills.map { canvas($0, place) }, close: false))\" fill=\"none\" stroke=\"\(hex(cutout))\" stroke-width=\(String(format: "\"%.2f\"", TileL.hillWidth * place.unit)) stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
    body.append("<path d=\"\(svgPath(TileL.sun.map { canvas($0, place) }, close: true))\" fill=\"\(hex(c.tile))\"/>")
    if let baseline = place.baseline {
        let word = wordPath(size: place.fontSize)
        var move = CGAffineTransform(translationX: baseline.x, y: baseline.y)
        if let moved = word.path.copy(using: &move) {
            body.append("<path d=\"\(svgPath(moved))\" fill=\"\(hex(c.ink))\"/>")
        }
    }
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(place.size.width))" height="\(Int(place.size.height))" viewBox="0 0 \(Int(place.size.width)) \(Int(place.size.height))">
    <title>Luminux</title>
    \(body.joined(separator: "\n"))
    </svg>

    """
}

// MARK: PNG

func rgb(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

func png(_ variant: Variant, scale: CGFloat) -> Data {
    let place = placement(for: variant.layout), c = variant.colors
    let width = Int(place.size.width * scale), height = Int(place.size.height * scale)
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    let cutout = c.background ?? 0xFFFFFF
    if let background = c.background {
        context.setFillColor(rgb(background))
        context.fill(CGRect(origin: .zero, size: place.size))
    }
    func fill(_ points: [CGPoint], _ color: CGColor) {
        context.setFillColor(color)
        context.addLines(between: points.map { canvas($0, place) })
        context.closePath()
        context.fillPath()
    }
    fill(TileL.tallCorners, rgb(c.tile, c.tallOpacity))
    let wide = TileL.wide
    fill([wide.origin, CGPoint(x: wide.maxX, y: wide.minY), CGPoint(x: wide.maxX, y: wide.maxY), CGPoint(x: wide.minX, y: wide.maxY)], rgb(c.tile))
    context.setStrokeColor(rgb(cutout))
    context.setLineWidth(TileL.hillWidth * place.unit)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addLines(between: TileL.hills.map { canvas($0, place) })
    context.strokePath()
    fill(TileL.sun, rgb(c.tile))
    if let baseline = place.baseline {
        let word = wordPath(size: place.fontSize)
        context.saveGState()
        context.translateBy(x: baseline.x, y: baseline.y)
        context.addPath(word.path)
        context.setFillColor(rgb(c.ink))
        context.fillPath()
        context.restoreGState()
    }
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
for variant in variants {
    try svg(variant).write(toFile: "\(outputDir)/\(variant.name).svg", atomically: true, encoding: .utf8)
    try png(variant, scale: variant.layout == .icon ? 1 : 2).write(to: URL(fileURLWithPath: "\(outputDir)/\(variant.name).png"))
    print("wrote \(variant.name)")
}
