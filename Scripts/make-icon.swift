import AppKit

// Genera Resources/AppIcon.icns (ejecutar: swift Scripts/make-icon.swift)
func render(_ px: Int) -> Data {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let s = CGFloat(px)
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.85, alpha: 1),
                        NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.45, alpha: 1)])!.draw(in: bg, angle: -90)
    // Mini treemap
    let tiles: [(CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.0, 0.0, 0.55, 0.62, .systemOrange), (0.55, 0.0, 0.45, 0.38, .systemTeal),
        (0.55, 0.38, 0.25, 0.24, .systemPink), (0.80, 0.38, 0.20, 0.24, .systemYellow),
        (0.0, 0.62, 0.40, 0.38, .systemGreen), (0.40, 0.62, 0.60, 0.38, .systemPurple),
    ]
    let area = rect.insetBy(dx: s * 0.12, dy: s * 0.12)
    for t in tiles {
        let r = NSRect(x: area.minX + t.0 * area.width, y: area.minY + t.1 * area.height,
                       width: t.2 * area.width, height: t.3 * area.height).insetBy(dx: s * 0.01, dy: s * 0.01)
        t.4.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: r, xRadius: s * 0.025, yRadius: s * 0.025).fill()
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let dir = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
