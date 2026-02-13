#!/usr/bin/env swift
// Generates a 1024x1024 AppIcon PNG for AIUsageMonitor.
// Design: Gradient indigo→teal rounded rect with a white circular gauge arc.
// Usage: swift generate_icon.swift /path/to/output.png

import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/AIUsageMonitorIcon.png"

let size = 1024
let s = CGFloat(size)
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fprint("Failed to create CGContext")
    exit(1)
}

// -- 1. Rounded-rect background with indigo→teal gradient -----------------
let rect = CGRect(x: 0, y: 0, width: s, height: s)
let cornerRadius: CGFloat = 220
let bgPath = CGMutablePath()
bgPath.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
ctx.addPath(bgPath)
ctx.clip()

// Gradient: deep indigo (bottom-left) → teal (top-right)
let gradientColors = [
    CGColor(red: 0.15, green: 0.10, blue: 0.40, alpha: 1.0), // deep indigo
    CGColor(red: 0.10, green: 0.55, blue: 0.60, alpha: 1.0), // teal
] as CFArray
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradientColors,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: s, y: s),
    options: []
)

// Reset clip for subsequent drawing
ctx.resetClip()

// -- 2. Circular gauge arc (white, ~70% filled) ---------------------------
let center = CGPoint(x: s / 2, y: s / 2)
let gaugeRadius: CGFloat = 320
let lineWidth: CGFloat = 60

// Background track (subtle white, full circle)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.round)
let startAngle: CGFloat = .pi * 0.75   // 7 o'clock position
let endAngle: CGFloat = .pi * 0.25     // 5 o'clock position (270° arc range)
ctx.addArc(
    center: center,
    radius: gaugeRadius,
    startAngle: startAngle,
    endAngle: endAngle,
    clockwise: true
)
ctx.strokePath()

// Foreground arc (~70% of the 270° range)
let arcRange: CGFloat = -.pi * 1.5  // total 270° going clockwise
let fillFraction: CGFloat = 0.70
let fillEndAngle = startAngle + arcRange * fillFraction

// Bright white arc
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.round)
ctx.addArc(
    center: center,
    radius: gaugeRadius,
    startAngle: startAngle,
    endAngle: fillEndAngle,
    clockwise: true
)
ctx.strokePath()

// -- 3. Glowing accent dot at the arc endpoint ----------------------------
let dotX = center.x + gaugeRadius * cos(fillEndAngle)
let dotY = center.y + gaugeRadius * sin(fillEndAngle)
let dotRadius: CGFloat = 42

// Outer glow (amber, semi-transparent)
ctx.setFillColor(CGColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 0.5))
ctx.fillEllipse(in: CGRect(
    x: dotX - dotRadius * 1.6,
    y: dotY - dotRadius * 1.6,
    width: dotRadius * 3.2,
    height: dotRadius * 3.2
))

// Inner dot (bright amber)
ctx.setFillColor(CGColor(red: 1.0, green: 0.80, blue: 0.25, alpha: 1.0))
ctx.fillEllipse(in: CGRect(
    x: dotX - dotRadius,
    y: dotY - dotRadius,
    width: dotRadius * 2,
    height: dotRadius * 2
))

// -- 4. Percentage text "70" in the center --------------------------------
let fontSize: CGFloat = 200
let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
let attrString = NSAttributedString(string: "70", attributes: [
    .font: font,
    .foregroundColor: NSColor.white,
])
let line = CTLineCreateWithAttributedString(attrString)
let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
let textX = center.x - textBounds.width / 2 - textBounds.origin.x
let textY = center.y - textBounds.height / 2 - textBounds.origin.y

ctx.saveGState()
ctx.textPosition = CGPoint(x: textX, y: textY)
CTLineDraw(line, ctx)
ctx.restoreGState()

// Small "%" below the number
let pctFont = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 80, nil)
let pctString = NSAttributedString(string: "%", attributes: [
    .font: pctFont,
    .foregroundColor: NSColor(white: 1.0, alpha: 0.7),
])
let pctLine = CTLineCreateWithAttributedString(pctString)
let pctBounds = CTLineGetBoundsWithOptions(pctLine, .useOpticalBounds)
let pctX = center.x - pctBounds.width / 2 - pctBounds.origin.x
let pctY = center.y - textBounds.height / 2 - 80 - pctBounds.origin.y

ctx.saveGState()
ctx.textPosition = CGPoint(x: pctX, y: pctY)
CTLineDraw(pctLine, ctx)
ctx.restoreGState()

// -- 5. Export as PNG -----------------------------------------------------
guard let image = ctx.makeImage() else {
    fprint("Failed to create image")
    exit(1)
}
let nsImage = NSBitmapImageRep(cgImage: image)
guard let pngData = nsImage.representation(using: .png, properties: [:]) else {
    fprint("Failed to create PNG data")
    exit(1)
}
do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Icon written to \(outputPath)")
} catch {
    fprint("Failed to write icon: \(error)")
    exit(1)
}

func fprint(_ msg: String) {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
}
