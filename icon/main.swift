// Draws the app icon: icon/main.swift <output.iconset> <hand.svg|png>
//
// An homage to the early Mac OS X preferences icon: a light switch plate with
// four screws and a toggle on the left; on the right, instead of a logo, the
// middle finger from Microsoft's Fluent Emoji set.
import AppKit

let output = CommandLine.arguments[1]
guard let hand = NSImage(contentsOfFile: CommandLine.arguments[2]) else { fatalError("cannot read \(CommandLine.arguments[2])") }
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func screw(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat, angle: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -r * 0.15), blur: r * 0.4, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.setFillColor(NSColor(white: 0.78, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    let g = CGGradient(colorsSpace: space, colors: [NSColor(white: 0.97, alpha: 1).cgColor, NSColor(white: 0.62, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.clip()
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.35), startRadius: 0, endCenter: c, endRadius: r * 1.2, options: [])
    ctx.restoreGState()
    // Slot
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    ctx.setStrokeColor(NSColor(white: 0.35, alpha: 1).cgColor)
    ctx.setLineWidth(r * 0.28)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: -r * 0.62, y: 0))
    ctx.addLine(to: CGPoint(x: r * 0.62, y: 0))
    ctx.strokePath()
    ctx.restoreGState()
}

func draw(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    let k = s / 1024
    let space = CGColorSpaceCreateDeviceRGB()

    // Plate (inside the 824 pt icon grid, gently rounded like the 2001 icon)
    let plate = CGRect(x: 108 * k, y: 120 * k, width: 808 * k, height: 790 * k)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 34 * k, cornerHeight: 34 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18 * k), blur: 34 * k, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    ctx.addPath(platePath)
    ctx.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let plateGradient = CGGradient(colorsSpace: space, colors: [NSColor(white: 1.0, alpha: 1).cgColor, NSColor(white: 0.93, alpha: 1).cgColor,
                                                                NSColor(white: 0.80, alpha: 1).cgColor] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(plateGradient, start: CGPoint(x: plate.minX, y: plate.maxY), end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
    ctx.restoreGState()
    // Bevel
    ctx.addPath(CGPath(roundedRect: plate.insetBy(dx: 3 * k, dy: 3 * k), cornerWidth: 31 * k, cornerHeight: 31 * k, transform: nil))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
    ctx.setLineWidth(5 * k)
    ctx.strokePath()
    ctx.addPath(platePath)
    ctx.setStrokeColor(NSColor(white: 0.55, alpha: 1).cgColor)
    ctx.setLineWidth(3 * k)
    ctx.strokePath()

    // Groove between the two plates
    let grooveX = plate.minX + plate.width * 0.33
    ctx.setStrokeColor(NSColor(white: 0.62, alpha: 1).cgColor)
    ctx.setLineWidth(4 * k)
    ctx.move(to: CGPoint(x: grooveX, y: plate.minY + 6 * k)); ctx.addLine(to: CGPoint(x: grooveX, y: plate.maxY - 6 * k)); ctx.strokePath()
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.move(to: CGPoint(x: grooveX + 4 * k, y: plate.minY + 6 * k)); ctx.addLine(to: CGPoint(x: grooveX + 4 * k, y: plate.maxY - 6 * k)); ctx.strokePath()

    // Toggle switch
    let switchCenter = CGPoint(x: (plate.minX + grooveX) / 2, y: plate.midY)
    let slot = CGRect(x: switchCenter.x - 46 * k, y: switchCenter.y - 112 * k, width: 92 * k, height: 224 * k)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: slot, cornerWidth: 14 * k, cornerHeight: 14 * k, transform: nil))
    ctx.clip()
    let slotGradient = CGGradient(colorsSpace: space, colors: [NSColor(white: 0.55, alpha: 1).cgColor, NSColor(white: 0.86, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(slotGradient, start: CGPoint(x: slot.minX, y: slot.maxY), end: CGPoint(x: slot.minX, y: slot.minY), options: [])
    ctx.restoreGState()
    let lever = CGRect(x: switchCenter.x - 30 * k, y: switchCenter.y - 10 * k, width: 60 * k, height: 112 * k)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 18 * k, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(CGPath(roundedRect: lever, cornerWidth: 12 * k, cornerHeight: 12 * k, transform: nil))
    ctx.setFillColor(NSColor(white: 0.95, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: lever, cornerWidth: 12 * k, cornerHeight: 12 * k, transform: nil))
    ctx.clip()
    let leverGradient = CGGradient(colorsSpace: space, colors: [NSColor.white.cgColor, NSColor(white: 0.74, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(leverGradient, start: CGPoint(x: lever.minX, y: lever.maxY), end: CGPoint(x: lever.maxX, y: lever.minY), options: [])
    ctx.restoreGState()

    // Screws
    screw(ctx, center: CGPoint(x: switchCenter.x, y: plate.maxY - 92 * k), radius: 26 * k, angle: 0)
    screw(ctx, center: CGPoint(x: switchCenter.x, y: plate.minY + 92 * k), radius: 26 * k, angle: 0)
    screw(ctx, center: CGPoint(x: plate.maxX - 78 * k, y: plate.maxY - 78 * k), radius: 26 * k, angle: .pi / 4)
    screw(ctx, center: CGPoint(x: plate.maxX - 78 * k, y: plate.minY + 78 * k), radius: 26 * k, angle: .pi / 4)

    // Hand: the Fluent Emoji artwork (MIT, see icon/NOTICE)
    let right = CGRect(x: grooveX + 30 * k, y: plate.minY + 110 * k, width: plate.maxX - grooveX - 110 * k, height: plate.height - 220 * k)
    let side = min(right.width, right.height)
    let handBox = CGRect(x: right.midX - side / 2, y: right.midY - side / 2, width: side, height: side)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 22 * k, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    hand.draw(in: handBox, from: .zero, operation: .sourceOver, fraction: 1)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                     ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(size).write(to: URL(fileURLWithPath: "\(output)/icon_\(name).png"))
}
