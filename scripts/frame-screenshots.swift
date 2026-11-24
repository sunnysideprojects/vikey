// Puts @2x window screenshots side by side on a Sunny Side Projects screenshot backdrop:
// yolk-soft fill, radius-lg corners, 2 pt ink sticker border (brand book: "Screenshots").
//   swift scripts/frame-screenshots.swift <out.png> <shot1.png> [shot2.png ...]
// Capture shots with `screencapture -x -l <windowID>` (keeps the window shadow).
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { print("usage: frame-screenshots.swift out.png shot.png..."); exit(1) }
let shots = args.dropFirst().map { NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: $0)))! }

func hex(_ s: String) -> NSColor {
    let v = Int(s.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let yolkSoft = hex("#ffebb8"), ink = hex("#231c15")

// All sizes in pixels at @2x.
let pad = 56, gap = 24, radius: CGFloat = 40, border: CGFloat = 4
let width = pad * 2 + shots.map(\.pixelsWide).reduce(0, +) + gap * (shots.count - 1)
let height = pad * 2 + shots.map(\.pixelsHigh).max()!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let card = NSRect(x: 0, y: 0, width: width, height: height).insetBy(dx: border / 2, dy: border / 2)
let path = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)
yolkSoft.setFill()
path.fill()

var x = pad
for shot in shots {
    let y = (height - shot.pixelsHigh) / 2 // vertically centred
    // sourceOver so the window shadow blends onto the backdrop (plain draw(in:) copies alpha).
    shot.draw(in: NSRect(x: x, y: y, width: shot.pixelsWide, height: shot.pixelsHigh), from: .zero,
              operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    x += shot.pixelsWide + gap
}

path.lineWidth = border
ink.setStroke()
path.stroke()

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[0]))
print("✓ \(args[0]) \(width)×\(height)")
