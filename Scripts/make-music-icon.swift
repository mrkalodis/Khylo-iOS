// Makes the Khylo Music icon from the Khylo app icon: the same logo, with the grey
// triangle turned into three sound bars.
// Run: swift Scripts/make-music-icon.swift Swiftfin/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png \
//          Swiftfin/Resources/Assets.xcassets/AppIconMusic.appiconset/AppIconMusic.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fatalError("usage: make-music-icon <khylo icon> <output>") }

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(logo, in: CGRect(x: 0, y: 0, width: size, height: size))
let px = ctx.data!.assumingMemoryBound(to: UInt8.self)

// y counts from the top here. The hexagon's own dark, sampled from its upper middle.
func at(_ x: Int, _ y: Int) -> Int { (y * size + x) * 4 }
var sum = [0, 0, 0], count = 0
for y in 190 ..< 260 { for x in 440 ..< 580 { let i = at(x, y); for c in 0 ..< 3 { sum[c] += Int(px[i + c]) }; count += 1 } }
let fill = sum.map { UInt8($0 / count) }

// Take the grey triangle out: anything dark and not orange or cream on the right.
for y in 380 ..< 700 {
    for x in 568 ..< 870 {
        let i = at(x, y)
        let l = 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
        if l < 120 { px[i] = fill[0]; px[i + 1] = fill[1]; px[i + 2] = fill[2] }
    }
}

// Three bars where it was; the middle one is the tallest, as tall as the triangle was.
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, 1])! }
let centerX: CGFloat = 705, centerY: CGFloat = CGFloat(size) - 535
let width: CGFloat = 58, gap: CGFloat = 40
let heights: [CGFloat] = [150, 280, 200]
var x = centerX - (3 * width + 2 * gap) / 2
for (index, height) in heights.enumerated() {
    let rect = CGRect(x: x, y: centerY - height / 2, width: width, height: height)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
    ctx.setFillColor(index == 1 ? color(244, 239, 232) : color(66, 69, 74))
    ctx.fillPath()
    x += width + gap
}

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
