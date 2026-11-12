// Draws the Vigil app icon (a cup of coffee with amber steam) and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>   (scripts/make-icon.sh wraps this and runs iconutil)
//
// Everything is vector code, so the icon is reproducible and has no third-party artwork.
// Each size is rendered at its own pixel size rather than downscaled, so small sizes stay crisp.
import AppKit

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Everything is drawn in a 1024 x 1024 space; the caller scales to the target pixel size.
func drawIcon() {
    // macOS icon grid: an 824-pt rounded square centred in the 1024 canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    // Soft shadow under the whole shape.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 28
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.set()
    color(0x241610).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    // Espresso background, lighter at the top.
    NSGradient(colors: [color(0x4B2E1F), color(0x1C110B)])!.draw(in: body, angle: -90)

    // Warm glow behind the cup: "the lights are on".
    NSGradient(colors: [color(0xFF9F0A, 0.40), color(0xFF9F0A, 0.0)])!.draw(
        fromCenter: NSPoint(x: 520, y: 500), radius: 0,
        toCenter: NSPoint(x: 520, y: 500), radius: 430, options: []
    )

    let cream = color(0xF6E8D4)
    let creamShade = color(0xE3CCAA)

    // Saucer.
    color(0xC9AE88).setFill()
    NSBezierPath(roundedRect: NSRect(x: 232, y: 292, width: 480, height: 44), xRadius: 22, yRadius: 22).fill()

    // Handle (behind the cup body).
    let handle = NSBezierPath()
    handle.appendArc(withCenter: NSPoint(x: 650, y: 478), radius: 78, startAngle: -85, endAngle: 85)
    handle.lineWidth = 48
    handle.lineCapStyle = .round
    creamShade.setStroke()
    handle.stroke()

    // Cup body.
    let cup = NSBezierPath()
    cup.move(to: NSPoint(x: 292, y: 610))
    cup.line(to: NSPoint(x: 652, y: 610))
    cup.line(to: NSPoint(x: 652, y: 460))
    cup.curve(to: NSPoint(x: 532, y: 334), controlPoint1: NSPoint(x: 652, y: 395), controlPoint2: NSPoint(x: 600, y: 334))
    cup.line(to: NSPoint(x: 412, y: 334))
    cup.curve(to: NSPoint(x: 292, y: 460), controlPoint1: NSPoint(x: 344, y: 334), controlPoint2: NSPoint(x: 292, y: 395))
    cup.close()
    NSGradient(colors: [cream, creamShade])!.draw(in: cup, angle: -90)

    // Rim and coffee surface.
    cream.setFill()
    NSBezierPath(ovalIn: NSRect(x: 292, y: 588, width: 360, height: 44)).fill()
    color(0x5A361F).setFill()
    NSBezierPath(ovalIn: NSRect(x: 308, y: 595, width: 328, height: 31)).fill()

    // Steam: three amber curls.
    func steam(x: CGFloat, base: CGFloat, height: CGFloat, alpha: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x, y: base))
        p.curve(to: NSPoint(x: x, y: base + height),
                controlPoint1: NSPoint(x: x - 46, y: base + height * 0.35),
                controlPoint2: NSPoint(x: x + 46, y: base + height * 0.65))
        p.lineWidth = 34
        p.lineCapStyle = .round
        color(0xFFB340, alpha).setStroke()
        p.stroke()
    }
    steam(x: 400, base: 668, height: 100, alpha: 0.85)
    steam(x: 472, base: 676, height: 150, alpha: 1.0)
    steam(x: 544, base: 668, height: 108, alpha: 0.85)

    NSGraphicsContext.restoreGraphicsState()

    // Thin rim light on the edge of the shape.
    color(0xFFFFFF, 0.10).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
    rim.lineWidth = 4
    rim.stroke()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// The ten files iconutil expects.
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    try png(pixels: pixels).write(to: outDir.appendingPathComponent("\(name).png"))
}
print("Wrote \(sizes.count) icon images to \(outDir.path)")
