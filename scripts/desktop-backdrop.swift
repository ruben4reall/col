// swift scripts/desktop-backdrop.swift <desktop.png> [points] [level]: shows the website's macOS desktop over the whole
// screen, just under the island (above the menu bar), until it is killed. The island's glass then shows the very desktop
// the website lays its captures on, and nothing of the Mac they were taken on. With a number of points, the desktop is
// raised by that much, to put a busier part of it (the lake) behind the island. With a window level (0 for the normal
// one), the desktop lies that low instead: under the drawers, which hang over the menu bar.
import AppKit

let image = NSImage(contentsOfFile: CommandLine.arguments[1])!
let raise = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 0
let level = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 26
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!.frame
let window = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
let view = NSImageView(frame: NSRect(x: 0, y: raise, width: screen.width, height: screen.height))
view.image = image
view.imageScaling = .scaleAxesIndependently
let content = NSView(frame: NSRect(origin: .zero, size: screen.size))
content.wantsLayer = true
content.layer?.backgroundColor = NSColor.black.cgColor
content.addSubview(view)
window.contentView = content
// The island floats at the status window level (25) plus 2; the menu bar sits at 24.
window.level = NSWindow.Level(rawValue: level)
window.ignoresMouseEvents = true
window.orderFrontRegardless()
app.run()
