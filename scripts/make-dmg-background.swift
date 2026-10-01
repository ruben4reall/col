// swift scripts/make-dmg-background.swift [output.png]
//
// The installer window's background: 660 x 400 points, rendered at 2x. scripts/release.sh places Col's icon at
// (165, 205) and Applications at (495, 205), in Finder's coordinates (points from the top left), with 112-point icons.
//
// Light on purpose: Finder draws the labels under the icons in black on any window with a background picture, whatever
// the appearance, so a Night ground would hide "Col" and "Applications". The blue comes back as the lit notch at the
// top edge, the icon's own window.
import AppKit

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

// Brand tokens (brand/README.md).
let night = color("#05080A"), blue = color("#0A84FF"), deep = color("#0060DF"), sky = color("#B8DAFF")
let ink = color("#0F1B1F"), graphite = color("#6E6E73")
let white = color("#FFFFFF"), paper = color("#F5F5F7")

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "brand/installer/dmg-background.png"
let width: CGFloat = 660, height: CGFloat = 400, scale = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)   // 144 dpi: Finder shows it at 660 x 400 points

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// Drawing coordinates start at the bottom left: Finder's y = 205 is 400 - 205 = 195 here.

// 1. The ground: White at the top, Paper at the bottom.
NSGradient(colors: [paper, white])!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

// 2. The notch, hanging from the top edge, with its blue glow below: the island, closed.
let notch = NSRect(x: (width - 150) / 2, y: height - 30, width: 150, height: 30)
let glow = NSGradient(colors: [blue.withAlphaComponent(0.28), sky.withAlphaComponent(0.10), white.withAlphaComponent(0)],
                      atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
glow.draw(fromCenter: NSPoint(x: width / 2, y: height - 20), radius: 0,
          toCenter: NSPoint(x: width / 2, y: height - 20), radius: 150, options: [])
let notchPath = NSBezierPath()
let r: CGFloat = 12, flare: CGFloat = 8
notchPath.move(to: NSPoint(x: notch.minX - flare, y: height))
notchPath.curve(to: NSPoint(x: notch.minX, y: height - flare), controlPoint1: NSPoint(x: notch.minX - flare / 3, y: height),
                controlPoint2: NSPoint(x: notch.minX, y: height - flare / 3))
notchPath.line(to: NSPoint(x: notch.minX, y: notch.minY + r))
notchPath.curve(to: NSPoint(x: notch.minX + r, y: notch.minY), controlPoint1: NSPoint(x: notch.minX, y: notch.minY + r / 2.2),
                controlPoint2: NSPoint(x: notch.minX + r / 2.2, y: notch.minY))
notchPath.line(to: NSPoint(x: notch.maxX - r, y: notch.minY))
notchPath.curve(to: NSPoint(x: notch.maxX, y: notch.minY + r), controlPoint1: NSPoint(x: notch.maxX - r / 2.2, y: notch.minY),
                controlPoint2: NSPoint(x: notch.maxX, y: notch.minY + r / 2.2))
notchPath.line(to: NSPoint(x: notch.maxX, y: height - flare))
notchPath.curve(to: NSPoint(x: notch.maxX + flare, y: height), controlPoint1: NSPoint(x: notch.maxX, y: height - flare / 3),
                controlPoint2: NSPoint(x: notch.maxX + flare / 3, y: height))
notchPath.close()
night.setFill()
notchPath.fill()
// The blue dot of a live activity, in the notch's right wing.
blue.setFill()
NSBezierPath(ovalIn: NSRect(x: notch.maxX - 26, y: notch.minY + 11, width: 8, height: 8)).fill()

// 3. The arrow from Col to Applications, at icon height, blue fading into its deeper shade.
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 262, y: 195))
arrow.line(to: NSPoint(x: 398, y: 195))
arrow.move(to: NSPoint(x: 380, y: 212))
arrow.line(to: NSPoint(x: 398, y: 195))
arrow.line(to: NSPoint(x: 380, y: 178))
deep.withAlphaComponent(0.85).setStroke()
arrow.stroke()

// 4. What to do, then who Col is not.
func centered(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let textWidth = (text as NSString).size(withAttributes: attributes).width
    (text as NSString).draw(at: NSPoint(x: (width - textWidth) / 2, y: y), withAttributes: attributes)
}
centered("Drag Col to Applications.", size: 13, weight: .medium, color: ink, y: 58)
centered("Free and open source, MIT License. Col is not affiliated with Apple.", size: 10.5, weight: .regular,
         color: graphite, y: 26)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print(output)
