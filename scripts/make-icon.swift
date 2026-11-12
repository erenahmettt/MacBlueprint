import AppKit
import CoreGraphics

// MacBlueprint icon: a blueprint sheet with a laptop drawn on it, showing a checklist.
let size = 1024
let output = CommandLine.arguments[1]

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// macOS icon grid: 824 × 824 body centered in 1024, with a soft shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(shape)
ctx.setFillColor(color(0x1A47D6))
ctx.fillPath()
ctx.restoreGState()

// Blueprint paper: vertical gradient plus a fine grid.
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let gradient = CGGradient(colorsSpace: space, colors: [color(0x2F6DFF), color(0x0F2F9E)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

let cell: CGFloat = 824 / 20
for i in 1..<20 {
    let offset = 100 + CGFloat(i) * cell
    let major = i % 4 == 0
    ctx.setStrokeColor(color(0xFFFFFF, major ? 0.16 : 0.07))
    ctx.setLineWidth(major ? 3 : 2)
    ctx.move(to: CGPoint(x: offset, y: 100)); ctx.addLine(to: CGPoint(x: offset, y: 924))
    ctx.move(to: CGPoint(x: 100, y: offset)); ctx.addLine(to: CGPoint(x: 924, y: offset))
    ctx.strokePath()
}
ctx.restoreGState()

ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let white = color(0xFFFFFF)

// Dimension line above the screen, like on a technical drawing.
ctx.setStrokeColor(color(0xFFFFFF, 0.55))
ctx.setLineWidth(6)
ctx.setLineDash(phase: 0, lengths: [18, 14])
ctx.move(to: CGPoint(x: 292, y: 772)); ctx.addLine(to: CGPoint(x: 732, y: 772))
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
for x in [CGFloat(282), 742] {
    ctx.move(to: CGPoint(x: x, y: 750)); ctx.addLine(to: CGPoint(x: x, y: 794))
}
ctx.strokePath()

// Laptop: screen and base.
let screen = CGRect(x: 282, y: 418, width: 460, height: 300)
ctx.setStrokeColor(white)
ctx.setLineWidth(24)
ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 34, cornerHeight: 34, transform: nil))
ctx.strokePath()

let base = CGMutablePath()
base.move(to: CGPoint(x: 214, y: 372))
base.addLine(to: CGPoint(x: 810, y: 372))
base.addQuadCurve(to: CGPoint(x: 770, y: 334), control: CGPoint(x: 806, y: 334))
base.addLine(to: CGPoint(x: 254, y: 334))
base.addQuadCurve(to: CGPoint(x: 214, y: 372), control: CGPoint(x: 218, y: 334))
base.closeSubpath()
ctx.addPath(base)
ctx.setFillColor(white)
ctx.fillPath()

// Checklist on the screen: two items done, one still open.
for (index, y) in [CGFloat(640), 568, 496].enumerated() {
    let done = index < 2
    ctx.setStrokeColor(done ? white : color(0xFFFFFF, 0.6))
    ctx.setLineWidth(16)
    if done {
        ctx.move(to: CGPoint(x: 336, y: y))
        ctx.addLine(to: CGPoint(x: 356, y: y - 20))
        ctx.addLine(to: CGPoint(x: 392, y: y + 18))
    } else {
        ctx.addEllipse(in: CGRect(x: 340, y: y - 20, width: 40, height: 40))
    }
    ctx.strokePath()
    ctx.setStrokeColor(color(0xFFFFFF, done ? 0.9 : 0.55))
    ctx.setLineWidth(18)
    ctx.move(to: CGPoint(x: 430, y: y)); ctx.addLine(to: CGPoint(x: index == 1 ? 610 : 680, y: y))
    ctx.strokePath()
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
