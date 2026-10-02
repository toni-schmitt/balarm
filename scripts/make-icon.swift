#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Renders the Balarm app icon (a dark squircle with a radial progress ring,
// echoing the app's own countdown UI) at every size iconutil requires, then
// packs the set into a single .icns.

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift make-icon.swift <output.icns>\n".data(using: .utf8)!)
    exit(2)
}
let outputPath = CommandLine.arguments[1]

// MARK: - Squircle path

/// Builds a closed path for a rounded rect whose corners follow a quarter
/// superellipse rather than a circular arc, which reads as a continuous
/// "squircle" corner instead of the sharper transition of a plain rounded
/// rect — matching the macOS Big Sur+ icon grid so the icon isn't boxed into
/// a legacy frame.
func squirclePath(rect: CGRect, radius: CGFloat, exponent: CGFloat = 5, samplesPerCorner: Int = 48) -> CGPath {
    let path = CGMutablePath()
    let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
    let r = radius

    func local(_ t: CGFloat) -> (CGFloat, CGFloat) {
        let lx = r * pow(cos(t), 2 / exponent)
        let ly = r * pow(sin(t), 2 / exponent)
        return (lx, ly)
    }

    // Each corner's offset is the same quarter superellipse rotated/reflected
    // so all four can be sampled with t going 0...pi/2 and chained directly
    // with straight edges in between (no separate line-drawing step needed).
    let corners: [(center: CGPoint, offset: (CGFloat, CGFloat) -> CGPoint)] = [
        (CGPoint(x: minX + r, y: minY + r), { (lx, ly) in CGPoint(x: -lx, y: -ly) }),
        (CGPoint(x: maxX - r, y: minY + r), { (lx, ly) in CGPoint(x: ly, y: -lx) }),
        (CGPoint(x: maxX - r, y: maxY - r), { (lx, ly) in CGPoint(x: lx, y: ly) }),
        (CGPoint(x: minX + r, y: maxY - r), { (lx, ly) in CGPoint(x: -ly, y: lx) }),
    ]

    var isFirst = true
    for corner in corners {
        for i in 0...samplesPerCorner {
            let t = (CGFloat(i) / CGFloat(samplesPerCorner)) * (CGFloat.pi / 2)
            let (lx, ly) = local(t)
            let offset = corner.offset(lx, ly)
            let point = CGPoint(x: corner.center.x + offset.x, y: corner.center.y + offset.y)
            if isFirst {
                path.move(to: point)
                isFirst = false
            } else {
                path.addLine(to: point)
            }
        }
    }
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

// MARK: - Drawing

/// Drawing happens in a fixed 1024x1024 reference space; the caller scales
/// the CTM to the target pixel size first, so every size is rendered from
/// the same vector description instead of being downscaled from one bitmap.
func drawIcon(in ctx: CGContext) {
    let canvas: CGFloat = 1024
    let margin: CGFloat = 100
    let bodyRect = CGRect(x: margin, y: margin, width: canvas - 2 * margin, height: canvas - 2 * margin)
    let cornerRadius: CGFloat = 185
    let bodyPath = squirclePath(rect: bodyRect, radius: cornerRadius)

    // Cast the drop shadow from an opaque fill, then paint the real gradient
    // on top with no shadow set, so the shadow only shows outside the shape
    // instead of muddying the gradient itself.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0x000000, alpha: 0.30))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let bodyGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x2B2D33), color(0x121316)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bodyGradient, start: CGPoint(x: canvas / 2, y: bodyRect.maxY), end: CGPoint(x: canvas / 2, y: bodyRect.minY), options: [])
    ctx.restoreGState()

    // Faint glassy highlight along the inner top edge; the gradient's own
    // falloff keeps it from reading as a full inner border.
    ctx.saveGState()
    let insetRect = bodyRect.insetBy(dx: 1.5, dy: 1.5)
    let highlightPath = squirclePath(rect: insetRect, radius: cornerRadius - 1.5)
    ctx.addPath(highlightPath)
    ctx.setLineWidth(2)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let highlightGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0xFFFFFF, alpha: 0.35), color(0xFFFFFF, alpha: 0.0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(highlightGradient, start: CGPoint(x: canvas / 2, y: bodyRect.maxY), end: CGPoint(x: canvas / 2, y: bodyRect.maxY - bodyRect.height * 0.35), options: [])
    ctx.restoreGState()

    let ringCenter = CGPoint(x: canvas / 2, y: canvas / 2)
    let ringRadius: CGFloat = 260
    let strokeWidth: CGFloat = 56

    ctx.saveGState()
    ctx.setLineWidth(strokeWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.12))
    ctx.addArc(center: ringCenter, radius: ringRadius, startAngle: 0, endAngle: 2 * CGFloat.pi, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // 12 o'clock, sweeping clockwise for 72% of the circle.
    let startAngle = CGFloat.pi / 2
    let sweep: CGFloat = 0.72 * 2 * CGFloat.pi
    let endAngle = startAngle - sweep
    let startPoint = CGPoint(x: ringCenter.x + ringRadius * cos(startAngle), y: ringCenter.y + ringRadius * sin(startAngle))
    let endPoint = CGPoint(x: ringCenter.x + ringRadius * cos(endAngle), y: ringCenter.y + ringRadius * sin(endAngle))

    ctx.saveGState()
    let arcPath = CGMutablePath()
    arcPath.addArc(center: ringCenter, radius: ringRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    ctx.addPath(arcPath)
    ctx.setLineWidth(strokeWidth)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    // Extend the gradient past its two endpoints — otherwise the stroke's
    // round caps (which sit outside the start/end points along the ring)
    // would be left unpainted and show the track color through the clip.
    let progressGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x0A84FF), color(0x64B5FF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(progressGradient, start: startPoint, end: endPoint, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    ctx.saveGState()
    let dotDiameter = strokeWidth * 0.55
    let dotRect = CGRect(x: endPoint.x - dotDiameter / 2, y: endPoint.y - dotDiameter / 2, width: dotDiameter, height: dotDiameter)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: dotRect)
    ctx.restoreGState()
}

// MARK: - Rendering to exact pixel sizes

func renderPNG(pixelSize: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    // 1 point == 1 pixel here, so the CTM scale below is the only scaling
    // applied and Retina backing doesn't double it.
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not create bitmap context for size \(pixelSize)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    cg.saveGState()
    cg.scaleBy(x: CGFloat(pixelSize) / 1024.0, y: CGFloat(pixelSize) / 1024.0)
    drawIcon(in: cg)
    cg.restoreGState()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode PNG for size \(pixelSize)")
    }
    return data
}

// MARK: - iconset assembly

let iconsetSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("balarm-icon-\(UUID().uuidString)")
let iconsetDir = tempDir.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for entry in iconsetSizes {
    let data = renderPNG(pixelSize: entry.pixels)
    let fileURL = iconsetDir.appendingPathComponent("\(entry.name).png")
    try data.write(to: fileURL)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputPath]
try process.run()
process.waitUntilExit()

try? FileManager.default.removeItem(at: tempDir)

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(process.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}

print("Wrote \(outputPath)")
