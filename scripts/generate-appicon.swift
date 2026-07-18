#!/usr/bin/env swift
// Renders the FlowBridge app icon: the Linea Viva "dictate" glyph (three
// breathing bars + cradle + stem, 24×24 grid, round caps) in white over the
// brand violet gradient. Usage: swift scripts/generate-appicon.swift <out.png>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: generate-appicon.swift <out.png>\n".utf8))
    exit(1)
}
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// Background: grad-accent (#8B77F6 → #6F58EC), top to bottom.
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0x8B77F6), rgb(0x6F58EC)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: size / 2, y: size),
    end: CGPoint(x: size / 2, y: 0),
    options: []
)

// Soft aurora accents so the tile isn't flat (kept subtle).
func pool(_ hex: UInt32, alpha: CGFloat, center: CGPoint, radius: CGFloat) {
    let colors = [rgb(hex).copy(alpha: alpha)!, rgb(hex).copy(alpha: 0)!] as CFArray
    let g = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}
pool(0xFB8C2E, alpha: 0.16, center: CGPoint(x: size * 0.85, y: size * 0.88), radius: size * 0.55)
pool(0xD5CCF7, alpha: 0.22, center: CGPoint(x: size * 0.14, y: size * 0.12), radius: size * 0.6)

// Glyph in a flipped (y-down) space so the 24-grid coordinates match the app.
ctx.saveGState()
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

let grid: CGFloat = 24
let glyphBox = size * 0.70
let scale = glyphBox / grid
ctx.translateBy(x: (size - glyphBox) / 2, y: (size - glyphBox) / 2)
ctx.scaleBy(x: scale, y: scale)

let path = CGMutablePath()
func bar(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) {
    path.move(to: CGPoint(x: x, y: y0))
    path.addLine(to: CGPoint(x: x, y: y1))
}
bar(9.7, 8.5, 13.5)
bar(12, 6.5, 15.5)
bar(14.3, 8.5, 13.5)
path.move(to: CGPoint(x: 7, y: 12.5))
path.addArc(
    center: CGPoint(x: 12, y: 12.5), radius: 5,
    startAngle: .pi, endAngle: 0, clockwise: true
)
bar(12, 18, 21)

ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(1.9)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setShadow(offset: CGSize(width: 0, height: -0.35), blur: 1.6, color: CGColor(srgbRed: 0.16, green: 0.09, blue: 0.45, alpha: 0.35))
ctx.addPath(path)
ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("failed to write \(outURL.path)\n".utf8))
    exit(1)
}
print("wrote \(outURL.path)")
