// Draws the Khylo Music app icon (1024 x 1024) from shapes, so it can be rebuilt exactly.
// Run: swift Scripts/make-music-icon.swift Swiftfin/Resources/Assets.xcassets/AppIconMusic.appiconset/AppIconMusic.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

let gradient = CGGradient(colorsSpace: space, colors: [color(0x1B1D22), color(0x0B0C0E)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])

let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 372

// Hexagon, point up.
let hex = CGMutablePath()
for k in 0 ..< 6 {
    let angle = CGFloat.pi / 2 - CGFloat(k) * CGFloat.pi / 3
    let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    k == 0 ? hex.move(to: p) : hex.addLine(to: p)
}
hex.closeSubpath()
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.setLineWidth(46)
ctx.addPath(hex)
ctx.setStrokeColor(color(0xF97316))
ctx.strokePath()

// Five sound bars in the middle; the centre one in the Khylo orange.
let heights: [CGFloat] = [150, 290, 400, 260, 130]
let barWidth: CGFloat = 52
let gap: CGFloat = 36
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = center.x - total / 2
for (index, height) in heights.enumerated() {
    let rect = CGRect(x: x, y: center.y - height / 2, width: barWidth, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(index == 2 ? color(0xF97316) : color(0xF4EFE8))
    ctx.fillPath()
    x += barWidth + gap
}

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
