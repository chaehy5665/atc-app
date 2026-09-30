// SPDX-License-Identifier: GPL-3.0-or-later
// Draws the app icon as an .iconset folder: a dark panel, one lit amber lamp and the plane symbol.
// Own drawing, no third-party art. Run on the Mac by build-app.sh:
//   swift Tools/make-icon.swift <out.iconset> && iconutil -c icns <out.iconset>
import AppKit

func render(pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Panel: rounded square with the usual icon margin.
    let panel = NSRect(x: size * 0.06, y: size * 0.06, width: size * 0.88, height: size * 0.88)
    let path = NSBezierPath(roundedRect: panel, xRadius: size * 0.2, yRadius: size * 0.2)
    NSGradient(colors: [NSColor(calibratedWhite: 0.20, alpha: 1), NSColor(calibratedWhite: 0.08, alpha: 1)])?
        .draw(in: path, angle: -90)

    // Lamp: an amber disc with a soft glow.
    let centre = NSPoint(x: size * 0.5, y: size * 0.5)
    let radius = size * 0.27
    let glow = NSGradient(colors: [NSColor(calibratedRed: 1, green: 0.62, blue: 0.1, alpha: 0.55), .clear])
    glow?.draw(fromCenter: centre, radius: radius * 0.6, toCenter: centre, radius: radius * 1.5, options: [])
    let lamp = NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    NSGradient(colors: [NSColor(calibratedRed: 1, green: 0.78, blue: 0.3, alpha: 1), NSColor(calibratedRed: 0.96, green: 0.5, blue: 0.05, alpha: 1)])?
        .draw(in: lamp, angle: -90)

    // Plane symbol on the lamp (SF Symbols ship with macOS).
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.3, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(calibratedWhite: 0.1, alpha: 1)]))
    if let plane = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = plane.size
        plane.draw(in: NSRect(x: centre.x - s.width / 2, y: centre.y - s.height / 2, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.iconset>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        guard let png = render(pixels: base * scale) else { fatalError("cannot render \(name)") }
        try png.write(to: out.appendingPathComponent(name))
    }
}
