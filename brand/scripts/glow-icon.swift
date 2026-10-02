// brand/scripts/glow-icon.swift: draws the Col icon, a slab of black glass with an island-shaped window lit in
// Apple blue from within. Usage: swift glow-icon.swift <capsule|notch> <out.png> [size]
import AppKit

let args = CommandLine.arguments
let variant = args.count > 1 ? args[1] : "notch"
let output = URL(fileURLWithPath: args.count > 2 ? args[2] : "icon.png")
let pixels = args.count > 3 ? Int(args[3])! : 1024

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func g(_ colors: [CGColor], _ l: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: l)! }

/// Superellipse-like rounded square, the macOS icon body.
func squircle(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

/// The island with its concave ears, hanging from `top` (y up).
func notch(cx: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat, ear: CGFloat, r: CGFloat) -> CGPath {
    let L = cx - w / 2, R = cx + w / 2, B = top - h, reach = min(r * 1.28, h - ear, w / 2), hd = reach * 0.36
    let p = CGMutablePath()
    p.move(to: CGPoint(x: L - ear, y: top)); p.addQuadCurve(to: CGPoint(x: L, y: top - ear), control: CGPoint(x: L, y: top))
    p.addLine(to: CGPoint(x: L, y: B + reach)); p.addCurve(to: CGPoint(x: L + reach, y: B), control1: CGPoint(x: L, y: B + hd), control2: CGPoint(x: L + hd, y: B))
    p.addLine(to: CGPoint(x: R - reach, y: B)); p.addCurve(to: CGPoint(x: R, y: B + reach), control1: CGPoint(x: R - hd, y: B), control2: CGPoint(x: R, y: B + hd))
    p.addLine(to: CGPoint(x: R, y: top - ear)); p.addQuadCurve(to: CGPoint(x: R + ear, y: top), control: CGPoint(x: R, y: top)); p.closeSubpath()
    return p
}

let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = squircle(body, 186)

// Drop shadow and the slab of black glass.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: c(0x000000, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(c(0x0A0A0B)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(bodyPath); ctx.clip()
ctx.drawLinearGradient(g([c(0x2A2B2F), c(0x121214), c(0x060607)], [0, 0.45, 1]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// A soft sheen across the top of the glass.
ctx.drawRadialGradient(g([c(0xFFFFFF, 0.10), c(0xFFFFFF, 0)], [0, 1]), startCenter: CGPoint(x: 512, y: 980), startRadius: 0, endCenter: CGPoint(x: 512, y: 980), endRadius: 560, options: [])
// A broad, soft reflection from the upper left, like polished black glass.
ctx.drawLinearGradient(g([c(0xFFFFFF, 0.06), c(0xFFFFFF, 0)], [0, 1]), start: CGPoint(x: 100, y: 924), end: CGPoint(x: 520, y: 420), options: [])

// The window.
let window: CGPath
let lightBottom: CGFloat, lightTop: CGFloat
if variant == "notch" {
    window = notch(cx: 512, top: 924, w: 392, h: 300, ear: 30, r: 96)
    lightTop = 924; lightBottom = 624
} else {
    let r = CGRect(x: 192, y: 382, width: 640, height: 260)
    window = CGPath(roundedRect: r, cornerWidth: 130, cornerHeight: 130, transform: nil)
    lightTop = r.maxY; lightBottom = r.minY
}
// Blue light spilling onto the black glass below the window.
ctx.drawRadialGradient(g([c(0x2F8BFF, 0.42), c(0x2F8BFF, 0)], [0, 1]), startCenter: CGPoint(x: 512, y: lightBottom - 10), startRadius: 0, endCenter: CGPoint(x: 512, y: lightBottom - 10), endRadius: 330, options: [])

// Inside the window: blue light rising from the bottom, deep navy at the top.
ctx.saveGState(); ctx.addPath(window); ctx.clip()
ctx.drawLinearGradient(g([c(0x020B24), c(0x0A3A9C), c(0x1677F2), c(0x6CB4FF), c(0xE4F2FF)], [0, 0.3, 0.62, 0.88, 1]),
                       start: CGPoint(x: 512, y: lightTop), end: CGPoint(x: 512, y: lightBottom), options: [])
// A brighter core low in the window, where the light comes from.
ctx.drawRadialGradient(g([c(0xEEF6FF, 0.55), c(0xEEF6FF, 0)], [0, 1]), startCenter: CGPoint(x: 512, y: lightBottom), startRadius: 0, endCenter: CGPoint(x: 512, y: lightBottom), endRadius: 260, options: [])
// Inner shadow: the window is recessed into the glass.
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: c(0x000000, 0.75))
let frame = CGMutablePath(); frame.addRect(body.insetBy(dx: -200, dy: -200)); frame.addPath(window)
ctx.addPath(frame); ctx.setFillColor(c(0x000000)); ctx.fillPath(using: .evenOdd)
ctx.restoreGState()
// A thin lit rim along the lower edge of the window.
ctx.saveGState(); ctx.addPath(window); ctx.setLineWidth(5); ctx.replacePathWithStrokedPath(); ctx.clip()
ctx.drawLinearGradient(g([c(0xFFFFFF, 0), c(0xCFE4FF, 0.2), c(0xE3F0FF, 0.95)], [0, 0.6, 1]), start: CGPoint(x: 512, y: lightTop), end: CGPoint(x: 512, y: lightBottom), options: [])
ctx.restoreGState()

// Edge of the slab: a fine highlight on the top rim, like polished glass.
ctx.addPath(bodyPath); ctx.setLineWidth(4); ctx.replacePathWithStrokedPath(); ctx.clip()
ctx.drawLinearGradient(g([c(0xFFFFFF, 0.35), c(0xFFFFFF, 0.04), c(0xFFFFFF, 0.1)], [0, 0.5, 1]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: output)
