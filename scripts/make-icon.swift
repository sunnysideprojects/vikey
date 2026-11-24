// Renders the ViKey app icon (1024 px PNG) in the Sunny Side Projects style:
// a cream keycap "sticker" (ink border + hard ink shadow) on a yolk macOS squircle.
//   swift scripts/make-icon.swift <out.png> [label]
// build-icon.sh turns the PNG into Resources/AppIcon.icns.
import AppKit
import CoreText

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "AppIcon-1024.png"
let label = args.count > 2 ? args[2] : "Vi"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("Resources/BricolageGrotesque-Variable.ttf") as CFURL, .process, nil)

func hex(_ s: String) -> NSColor {
    let v = Int(s.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let yolk = hex("#ffb703"), ink = hex("#231c15"), cream = hex("#fff8ec")

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824 pt body centred in 1024, corner radius ~185.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let drop = NSShadow()
drop.shadowColor = NSColor.black.withAlphaComponent(0.28)
drop.shadowOffset = NSSize(width: 0, height: -10)
drop.shadowBlurRadius = 24
drop.set()
yolk.setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()

// Keycap sticker: hard ink shadow offset down-right, then cream cap with ink border.
let border: CGFloat = 22, offset: CGFloat = 30
let cap = NSRect(x: 232, y: 262, width: 540, height: 540)
let shadowPath = NSBezierPath(roundedRect: cap.offsetBy(dx: offset, dy: -offset), xRadius: 96, yRadius: 96)
ink.setFill()
shadowPath.fill()
let capPath = NSBezierPath(roundedRect: cap, xRadius: 96, yRadius: 96)
cream.setFill()
capPath.fill()
capPath.lineWidth = border
ink.setStroke()
capPath.stroke()

// Label in Bricolage Grotesque ExtraBold (variable font: weight axis 800).
var font = NSFont(name: "BricolageGrotesque-Regular", size: 300) ?? NSFont.systemFont(ofSize: 300, weight: .heavy)
let wght = 0x77676874 // 'wght'
let desc = font.fontDescriptor.addingAttributes([.variation: [wght: 800]])
font = NSFont(descriptor: desc, size: 300) ?? font
let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: ink, .kern: -8])
let line = CTLineCreateWithAttributedString(text)
let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
let ctx = NSGraphicsContext.current!.cgContext
ctx.textPosition = CGPoint(x: cap.midX - glyphBounds.midX, y: cap.midY - glyphBounds.midY)
CTLineDraw(line, ctx)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("✓ \(out)")
