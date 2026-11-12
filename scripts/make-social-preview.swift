import AppKit

// Draws the 1280 × 640 image GitHub and LinkedIn show for a link to the repo.
// Usage: swift scripts/make-social-preview.swift <icon-1024.png> <output.png>
let iconPath = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let width = 1280, height = 640

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Blueprint paper, matching the app icon.
let gradient = NSGradient(starting: color(0x2F6DFF), ending: color(0x0F2F9E))!
gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)
let cell: CGFloat = 32
for i in 0...(width / Int(cell)) {
    let major = i % 4 == 0
    ctx.setStrokeColor(color(0xFFFFFF, major ? 0.12 : 0.05).cgColor)
    ctx.setLineWidth(major ? 2 : 1)
    let x = CGFloat(i) * cell
    ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: CGFloat(height)))
    if CGFloat(i) * cell <= CGFloat(height) {
        ctx.move(to: CGPoint(x: 0, y: x)); ctx.addLine(to: CGPoint(x: CGFloat(width), y: x))
    }
    ctx.strokePath()
}

// App icon on the left.
let icon = NSImage(contentsOfFile: iconPath)!
icon.draw(in: NSRect(x: 70, y: 150, width: 340, height: 340))

// Title, tagline and a footer line.
func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, at point: NSPoint) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color(0xFFFFFF, alpha),
        .kern: size > 60 ? -1.5 : 0,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(at: point)
}
draw("MacBlueprint", size: 92, weight: .bold, alpha: 1, at: NSPoint(x: 450, y: 352))
draw("Snapshot your Mac.", size: 40, weight: .medium, alpha: 0.95, at: NSPoint(x: 454, y: 284))
draw("Restore it on the next one.", size: 40, weight: .medium, alpha: 0.95, at: NSPoint(x: 454, y: 234))
draw("Native SwiftUI app and CLI  ·  Homebrew, App Store, VS Code  ·  Open source", size: 22, weight: .regular,
     alpha: 0.7, at: NSPoint(x: 456, y: 170))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
