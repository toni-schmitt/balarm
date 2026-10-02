#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Renders the Balarm app icon (a radial progress ring on a light plate, echoing
// the app's own countdown UI) at every size iconutil requires, then packs the
// set into a single .icns.
//
// The artwork is opaque and fills the whole canvas, with no rounded corners,
// padding or shadow of its own. macOS 26 clips such icons to its standard
// squircle and adds the glass rim; artwork with its own shape and transparent
// margins is instead shrunk into a grey "legacy" frame.

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift make-icon.swift <output.icns>\n".data(using: .utf8)!)
    exit(2)
}
let outputPath = CommandLine.arguments[1]

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

// MARK: - Drawing

/// Drawing happens in a fixed 1024x1024 reference space; the caller scales
/// the CTM to the target pixel size first, so every size is rendered from
/// the same vector description instead of being downscaled from one bitmap.
func drawIcon(in ctx: CGContext) {
    let canvas: CGFloat = 1024
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    // White-to-grey plate, the same family as Clock's and Calculator's.
    let plate = CGGradient(colorsSpace: sRGB, colors: [color(0xFFFFFF), color(0xDCDDE2)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(plate, start: CGPoint(x: 0, y: canvas), end: .zero, options: [])

    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let radius = canvas * 0.27
    let lineWidth = canvas * 0.085

    ctx.saveGState()
    ctx.setLineWidth(lineWidth)
    ctx.setStrokeColor(color(0x000000, alpha: 0.08))
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // 12 o'clock, sweeping clockwise for 72% of the circle (CoreGraphics is
    // y-up, so clockwise means decreasing angles).
    let startAngle = CGFloat.pi / 2
    let endAngle = startAngle - 0.72 * 2 * .pi
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    let arcShape = arc.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)

    // A soft shadow lifts the arc off the plate, the way layered system icons read.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.012), blur: canvas * 0.04, color: color(0x000000, alpha: 0.18))
    ctx.addPath(arcShape)
    ctx.setFillColor(color(0x0A84FF))
    ctx.fillPath()
    ctx.restoreGState()

    // Extend the gradient past its endpoints so the round caps are painted too.
    ctx.saveGState()
    ctx.addPath(arcShape)
    ctx.clip()
    let arcGradient = CGGradient(colorsSpace: sRGB, colors: [color(0x0A84FF), color(0x5AB3FF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        arcGradient,
        start: CGPoint(x: canvas * 0.7, y: canvas * 0.8),
        end: CGPoint(x: canvas * 0.3, y: canvas * 0.25),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    let tip = CGPoint(x: center.x + radius * cos(endAngle), y: center.y + radius * sin(endAngle))
    let dot = lineWidth * 0.45
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: tip.x - dot / 2, y: tip.y - dot / 2, width: dot, height: dot))
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
