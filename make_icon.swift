// Usage: swift make_icon.swift <output.icns>   — renders a simple gradient + sparkles icon.
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    // Black → #152331 (the app theme), with a faint silver rim and an orb glow behind the sparkles.
    NSGradient(colors: [NSColor.black, NSColor(red: 0x15 / 255, green: 0x23 / 255, blue: 0x31 / 255, alpha: 1)])!
        .draw(in: path, angle: -45)
    let orb = NSBezierPath(ovalIn: NSRect(x: s * 0.22, y: s * 0.22, width: s * 0.56, height: s * 0.56))
    NSGradient(colors: [NSColor(white: 1, alpha: 0.95), NSColor(red: 0.49, green: 0.54, blue: 0.60, alpha: 0.95),
                        NSColor(red: 0.83, green: 0.85, blue: 0.88, alpha: 0.95)])!.draw(in: orb, angle: 135)
    let core = NSBezierPath(ovalIn: NSRect(x: s * 0.255, y: s * 0.255, width: s * 0.49, height: s * 0.49))
    NSGradient(starting: NSColor(red: 0.16, green: 0.21, blue: 0.26, alpha: 1), ending: NSColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1))!
        .draw(in: core, relativeCenterPosition: NSPoint(x: -0.3, y: 0.4))
    NSColor(white: 1, alpha: 0.18).setStroke()
    path.lineWidth = max(1, s * 0.006); path.stroke()
    if let sym = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: s * 0.30, weight: .regular)) {
        let tinted = NSImage(size: sym.size, flipped: false) { r in
            sym.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
        }
        let sz = tinted.size
        tinted.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let set = out.deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
