#!/usr/bin/swift
//
//  GenerateAppIcon.swift — Côte d'OS
//
//  Draws the app icon and writes every size the asset catalog declares, plus a
//  flattened 1024 for marketing use. Pure CoreGraphics; there is no design file
//  and no export step to forget.
//
//      swift Tools/GenerateAppIcon.swift [outputDirectory]
//
//  Default output directory is the appiconset itself, so running this updates
//  the app. All geometry is written in a 1024 grid with the origin at the TOP
//  LEFT (the context is flipped), because that is how the layout reads.
//

import Foundation
import CoreGraphics
import ImageIO

// MARK: - Helpers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255,
        alpha,
    ])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: srgb,
               colors: stops.map { $0.1 } as CFArray,
               locations: stops.map { $0.0 })!
}

/// The macOS icon silhouette, as a superellipse rather than a rounded rect.
///
/// `CGPath(roundedRect:)` joins circular arcs to straight edges, and the seam
/// where curvature jumps from zero to 1/r is visible at icon sizes — it is the
/// single thing that most reliably makes a hand-drawn icon read as not-Apple.
/// A superellipse (|x/a|^n + |y/b|^n = 1) has continuous curvature all the way
/// round, which is what Apple's shape actually is. n ≈ 5 matches the Big Sur
/// mask closely.
func squircle(in rect: CGRect, exponent n: CGFloat = 5, segments: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    for i in 0...segments {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(segments)
        let c = cos(t), s = sin(t)
        // Signed powers, so all four quadrants come out of one expression.
        let x = cx + a * (abs(c) == 0 ? 0 : pow(abs(c), 2 / n)) * (c < 0 ? -1 : 1)
        let y = cy + b * (abs(s) == 0 ? 0 : pow(abs(s), 2 / n)) * (s < 0 ? -1 : 1)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Fully rounded on the short axis — `min`, not `height`, because the wave's bars
/// are taller than they are wide and a radius of half their *height* is clamped
/// into an ellipse. Which is what happened, and five ellipses in a row read as a
/// row of eggs rather than as a spectrum.
func capsule(_ rect: CGRect) -> CGPath {
    let r = min(rect.width, rect.height) / 2
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

// MARK: - Layout (1024 grid, origin top left)

/// Apple's grid: the artwork occupies 824 of the 1024 canvas, centred, and the
/// remaining 100 on each side is where the shadow lives. An icon drawn edge to
/// edge sits visibly larger than every other icon in the Dock.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)

/// The island, and it is the whole subject. Deliberately wide and tall enough to
/// survive being drawn at 32 px: the temptation is to draw the Mac around it,
/// which is what the previous icon did, and at small sizes that left a dark frame
/// with an empty middle.
let island = CGRect(x: 277, y: 417, width: 470, height: 190)

// MARK: - Drawing

/// - Parameter simplified: for 16 and 32 px. Three fat bars instead of five, no
///   glow — five bars land under a pixel each at that size and average out into
///   a grey smear, which reads as a blurry icon rather than a small one.
func drawIcon(into ctx: CGContext, side: CGFloat, simplified: Bool) {
    let k = side / 1024                       // one scale factor, applied once
    ctx.translateBy(x: 0, y: side)
    ctx.scaleBy(x: 1, y: -1)
    ctx.scaleBy(x: k, y: k)
    ctx.interpolationQuality = .high

    let plateShape = squircle(in: plate)

    // 1. Contact shadow. Offset down, never centred: a symmetric shadow reads as
    //    a glow and flattens the icon onto the background.
    if !simplified {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 46, color: color(0x000000, 0.42))
        ctx.addPath(plateShape)
        ctx.setFillColor(color(0x000000))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(plateShape)
    ctx.clip()

    // 2. The field. Violet is the app's colour; this runs deep indigo at the
    //    bottom to bright violet at the top so the light has a direction.
    ctx.drawLinearGradient(gradient([
        (0.00, color(0x9B72FF)),
        (0.34, color(0x7546E8)),
        (0.72, color(0x4A2A85)),
        (1.00, color(0x2A1850)),
    ]), start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

    // 3. Light source, top centre, elliptical. Apple's icons almost all have one
    //    and it is most of why they read as objects rather than as artwork.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 168)
    ctx.scaleBy(x: 1, y: 0.62)
    ctx.drawRadialGradient(gradient([
        (0.00, color(0xF3EBFF, 0.55)),
        (0.55, color(0xD9C2FF, 0.20)),
        (1.00, color(0xD9C2FF, 0.00)),
    ]), startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 520, options: [])
    ctx.restoreGState()

    // 4. Glass rim: a bright hairline inside the top edge, fading out by the
    //    shoulders. This is the cheapest depth cue there is.
    if !simplified {
        ctx.saveGState()
        ctx.addPath(plateShape)
        ctx.clip()
        ctx.setLineWidth(6)
        ctx.addPath(squircle(in: plate.insetBy(dx: 3, dy: 3)))
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient([
            (0.00, color(0xFFFFFF, 0.55)),
            (0.28, color(0xFFFFFF, 0.10)),
            (0.60, color(0xFFFFFF, 0.00)),
        ]), start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        ctx.restoreGState()
    }

    // 5. The island. Near-black rather than black, so it reads as a dark object
    //    on a lit surface instead of a hole cut in one.
    if !simplified {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x160B2E, 0.75))
        ctx.addPath(capsule(island))
        ctx.setFillColor(color(0x000000))
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(capsule(island))
    ctx.clip()
    ctx.drawLinearGradient(gradient([
        (0.00, color(0x1A1622)),
        (0.45, color(0x0B0910)),
        (1.00, color(0x000000)),
    ]), start: CGPoint(x: 512, y: island.minY), end: CGPoint(x: 512, y: island.maxY), options: [])

    // 5b. Specular along the island's own top edge — same trick, smaller.
    if !simplified {
        ctx.saveGState()
        ctx.setLineWidth(3.5)
        ctx.addPath(capsule(island.insetBy(dx: 2, dy: 2)))
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient([
            (0.00, color(0xC9B2FF, 0.42)),
            (0.35, color(0xC9B2FF, 0.06)),
            (1.00, color(0xC9B2FF, 0.00)),
        ]), start: CGPoint(x: 512, y: island.minY), end: CGPoint(x: 512, y: island.maxY), options: [])
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // 6. The wave. Heights are a still frame of a real spectrum — tallest in the
    //    middle, uneven either side — rather than a symmetric arch, which is what
    //    every equaliser glyph does and what makes them look like decoration.
    // The floor sits high (0.55, not 0.1) for a reason that is about drawing
    // rather than about audio: a capsule shorter than ~1.8× its width stops
    // reading as a bar and becomes an oval, and one oval in a row of bars is all
    // it takes to make the whole run look like decoration.
    // Simplified keeps the gaps *wider* than the bars. At 32 px a bar is about
    // 1.4 px and a gap 1.75 px; make the bars the wider of the two and the gaps
    // disappear into them on the downsample, which turns three bars into one
    // grey lozenge.
    let heights: [CGFloat] = simplified ? [0.68, 1.00, 0.84] : [0.55, 0.80, 1.00, 0.66, 0.90]
    let barWidth: CGFloat = simplified ? 46 : 40
    let gap: CGFloat = simplified ? 56 : 28
    let maxHeight: CGFloat = 140
    let run = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = island.midX - run / 2

    let bars = CGMutablePath()
    var rects: [CGRect] = []
    for h in heights {
        let barHeight = maxHeight * h
        let r = CGRect(x: x, y: island.midY - barHeight / 2, width: barWidth, height: barHeight)
        rects.append(r)
        bars.addPath(capsule(r))
        x += barWidth + gap
    }

    if !simplified {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 34, color: color(0xB08CFF, 0.85))
        ctx.addPath(bars)
        ctx.setFillColor(color(0xB08CFF))
        ctx.fillPath()
        ctx.restoreGState()
    }
    for r in rects {
        ctx.saveGState()
        ctx.addPath(capsule(r))
        ctx.clip()
        ctx.drawLinearGradient(gradient([
            (0.00, color(0xFFFFFF)),
            (0.45, color(0xEADDFF)),
            (1.00, color(0xB794FF)),
        ]), start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY), options: [])
        ctx.restoreGState()
    }

    ctx.restoreGState()   // plate clip
}

// MARK: - Rendering

func context(_ side: Int, opaque: Bool = false) -> CGContext {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
              space: srgb,
              bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
}

/// Rendered at 4× and downsampled, not drawn at the target size: the glow and
/// the gradients need the headroom, and CoreGraphics' high-quality downsample
/// beats its own antialiasing at 16 px by a wide margin.
func render(side: Int, simplified: Bool) -> CGImage {
    let superSide = side * 4
    let hi = context(superSide)
    drawIcon(into: hi, side: CGFloat(superSide), simplified: simplified)
    guard side != superSide, let image = hi.makeImage() else { return hi.makeImage()! }
    let out = context(side)
    out.interpolationQuality = .high
    out.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return out.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Output

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
               ? CommandLine.arguments[1]
               : "CoteDOs/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

// The seven files Contents.json points at. 16 and 32 get the simplified drawing.
for side in [16, 32, 64, 128, 256, 512, 1024] {
    let image = render(side: side, simplified: side <= 32)
    write(image, to: root.appendingPathComponent("icon_\(side).png"))
    print("✓ icon_\(side).png")
}

// Flattened, no alpha, and deliberately *not* in the appiconset — an image in
// there that no slot claims is an Xcode warning. Goes to assets/ for the README.
let marketing = URL(fileURLWithPath: "assets/icon.png")
if FileManager.default.fileExists(atPath: marketing.deletingLastPathComponent().path) {
    let flat = context(1024, opaque: true)
    flat.setFillColor(color(0xFFFFFF))
    flat.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    flat.draw(render(side: 1024, simplified: false), in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    write(flat.makeImage()!, to: marketing)
    print("✓ assets/icon.png (flattened, no alpha)")
}
