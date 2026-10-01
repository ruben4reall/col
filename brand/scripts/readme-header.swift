// swift brand/scripts/readme-header.swift: the README's header, 1600 x 480, in docs/images/readme-header.png (light)
// and readme-header-dark.png (dark). The icon, the name and the promise, as on the website.
import AppKit

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

let icon = NSImage(contentsOfFile: "brand/icon-1024.png")!
for dark in [false, true] {
    let width: CGFloat = 1600, height: CGFloat = 480
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let card = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height), xRadius: 36, yRadius: 36)
    (dark ? color("#0A0A0C") : color("#F5F5F7")).setFill()
    card.fill()
    card.addClip()
    // The blue light of the notch, from the top edge.
    NSGradient(colors: [color("#0A84FF", alpha: dark ? 0.32 : 0.18), color("#0A84FF", alpha: 0)])!
        .draw(fromCenter: NSPoint(x: width / 2, y: height + 40), radius: 0, toCenter: NSPoint(x: width / 2, y: height + 40), radius: 520, options: [])
    color("#000000").setFill(); NSBezierPath(roundedRect: NSRect(x: width / 2 - 150, y: height - 34, width: 300, height: 60), xRadius: 22, yRadius: 22).fill()

    icon.draw(in: NSRect(x: 250, y: 124, width: 232, height: 232))
    let ink = dark ? color("#F5F5F7") : color("#1D1D1F"), soft = dark ? color("#86868B") : color("#6E6E73")
    ("Col" as NSString).draw(at: NSPoint(x: 540, y: 238), withAttributes: [.font: NSFont.systemFont(ofSize: 128, weight: .semibold), .foregroundColor: ink, .kern: -3])
    ("The notch, made useful." as NSString).draw(at: NSPoint(x: 546, y: 176), withAttributes: [.font: NSFont.systemFont(ofSize: 44, weight: .semibold), .foregroundColor: ink, .kern: -0.5])
    ("Music, AirPods, files, timers and your AI agents, in the MacBook notch." as NSString).draw(at: NSPoint(x: 548, y: 128), withAttributes: [.font: NSFont.systemFont(ofSize: 26, weight: .regular), .foregroundColor: soft])
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dark ? "docs/images/readme-header-dark.png" : "docs/images/readme-header.png"))
}
print("docs/images/readme-header.png, docs/images/readme-header-dark.png")
