// swift scripts/compose-site.swift <desktop.png> <shots folder>: the website's figures, each a real capture of Col
// (from scripts/capture-site.sh) laid on the top of a real macOS desktop, both at 2x.
// Output: <shots folder>/figures/<name>.png, converted to WebP by the caller for the README. The website lays the
// captures on the desktop itself, with CSS.
import AppKit

/// Pixels exactly as stored in the file: NSImage would hand back a copy rendered for the screen.
func load(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

let desktopPath = CommandLine.arguments[1]
guard let desktop = load(desktopPath) else { fatalError("no desktop at \(desktopPath)") }
let shots = CommandLine.arguments[2], out = "\(shots)/figures"
try? FileManager.default.removeItem(atPath: out)
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

/// The top of the desktop around the notch, `span` x `rows` points (at 2x), with the notch at rest under the capture:
/// what a real screen shows, cropped close.
func figure(_ shot: String, span: Int = 720, rows: Int = 250, name: String) {
    guard let rest = load("\(shots)/rest.png"), let island = load("\(shots)/\(shot).png") else {
        print("missing \(shot)"); return
    }
    let width = span * 2, height = rows * 2
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let crop = desktop.cropping(to: CGRect(x: (desktop.width - width) / 2, y: 0, width: width, height: height))!
    context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
    for image in [rest, island] {
        context.draw(image, in: CGRect(x: (width - image.width) / 2, y: height - image.height, width: image.width, height: image.height))
    }
    try! NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    print("  \(name)")
}

figure("home-open", name: "open")
figure("agent-request", name: "agent")
figure("airpods-pro", name: "airpods-pro")
figure("airpods-max", name: "airpods-max")
