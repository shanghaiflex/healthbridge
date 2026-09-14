// Draws the BoW app icon: a body without organs — a thick pale ring, open at the bottom-right,
// one blue point where the gap is. Run: swift tools/icon.swift BoW/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let size = 1024.0
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Ground: near-black with a faint warm glow rising from the bottom.
ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.045, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
let glow = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1),
    CGColor(red: 0.04, green: 0.04, blue: 0.045, alpha: 0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: size * 0.5, y: size * 0.2), startRadius: 0,
                       endCenter: CGPoint(x: size * 0.5, y: size * 0.2), endRadius: size * 0.9, options: [])

// The ring, open between ~-70° and ~-20° (bottom-right).
let center = CGPoint(x: size / 2, y: size / 2)
let radius = size * 0.31
let width = size * 0.085
ctx.setLineWidth(width)
ctx.setLineCap(.round)
ctx.setStrokeColor(CGColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1))
let gapStart = -70.0 * .pi / 180, gapEnd = -18.0 * .pi / 180
ctx.addArc(center: center, radius: radius, startAngle: gapEnd, endAngle: gapStart + 2 * .pi, clockwise: false)
ctx.strokePath()

// The point in the gap.
let a = (gapStart + gapEnd) / 2
let dot = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
ctx.setFillColor(CGColor(red: 0.161, green: 0.592, blue: 1.0, alpha: 1))
ctx.fillEllipse(in: CGRect(x: dot.x - width * 0.55, y: dot.y - width * 0.55, width: width * 1.1, height: width * 1.1))

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
