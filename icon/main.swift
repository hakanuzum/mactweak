// Draws the app icon: icon/main.swift <output.iconset> <style: press|ink> <hand-flat.svg> <hand-lines.svg>
//
// A light switch plate in the early Aqua spirit, drawn as vector so every edge
// stays sharp. The plate is the macOS icon shape itself (824 pt in 1024), with a
// toggle switch, screws and a groove. On the right the middle finger (Fluent
// Emoji, MIT) is stamped into the plate:
//   press  pressed into the plastic (debossed: inner shadow, lit lower lip)
//   ink    a rubber stamp in ink, inside a seal ring with the app name
import AppKit

let args = CommandLine.arguments
let output = args[1], style = args[2]
guard let handFlat = NSImage(contentsOfFile: args[3]), let handLines = NSImage(contentsOfFile: args[4]) else {
    fatalError("cannot read hand artwork")
}
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let rgb = CGColorSpaceCreateDeviceRGB()

func gray(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(gray: w, alpha: a) }
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: locations)!
}
func rgbaContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: rgb,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Artwork rendered at a size, as a grayscale mask (for clipping) and as white-with-alpha.
struct Shape {
    let gray: CGImage
    let white: CGImage
}

func shape(_ image: NSImage, size: CGSize) -> Shape {
    let w = Int(size.width.rounded()), h = Int(size.height.rounded())
    let ctx = rgbaContext(w, h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    let src = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var g = [UInt8](repeating: 0, count: w * h)
    var wa = [UInt8](repeating: 0, count: w * h * 4)
    for i in 0..<(w * h) {
        let a = src[i * 4 + 3]
        g[i] = a
        wa[i * 4] = a; wa[i * 4 + 1] = a; wa[i * 4 + 2] = a; wa[i * 4 + 3] = a  // premultiplied white
    }
    let grayImg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                          provider: CGDataProvider(data: Data(g) as CFData)!, decode: nil,
                          shouldInterpolate: true, intent: .defaultIntent)!
    let whiteImg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: rgb,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: CGDataProvider(data: Data(wa) as CFData)!, decode: nil,
                           shouldInterpolate: true, intent: .defaultIntent)!
    return Shape(gray: grayImg, white: whiteImg)
}

func screw(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, angle: CGFloat, k: CGFloat) {
    let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    ctx.addEllipse(in: rect.insetBy(dx: -3 * k, dy: -3 * k))  // countersink
    ctx.setFillColor(gray(0.70))
    ctx.fillPath()
    ctx.saveGState()
    ctx.addEllipse(in: rect)
    ctx.clip()
    ctx.drawRadialGradient(gradient([gray(1), gray(0.80), gray(0.52)], [0, 0.55, 1]),
                           startCenter: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.4), startRadius: 0,
                           endCenter: c, endRadius: r * 1.15, options: [])
    ctx.restoreGState()
    ctx.addEllipse(in: rect)
    ctx.setStrokeColor(gray(0.32))
    ctx.setLineWidth(2.4 * k)
    ctx.strokePath()
    // Slot: dark cut with a light lower edge
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(gray(1, 0.85))
    ctx.setLineWidth(r * 0.30)
    ctx.move(to: CGPoint(x: -r * 0.6, y: -r * 0.08)); ctx.addLine(to: CGPoint(x: r * 0.6, y: -r * 0.08)); ctx.strokePath()
    ctx.setStrokeColor(gray(0.20))
    ctx.setLineWidth(r * 0.24)
    ctx.move(to: CGPoint(x: -r * 0.6, y: r * 0.04)); ctx.addLine(to: CGPoint(x: r * 0.6, y: r * 0.04)); ctx.strokePath()
    ctx.restoreGState()
}

func drawPlate(_ ctx: CGContext, k: CGFloat) -> (plate: CGRect, groove: CGFloat) {
    // Plate = the macOS icon shape (824 in 1024, corner 185)
    let plate = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let path = CGPath(roundedRect: plate, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * k), blur: 28 * k, color: gray(0, 0.35))
    ctx.addPath(path)
    ctx.setFillColor(gray(0.92))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([gray(1.0), gray(0.95), gray(0.83)], [0, 0.5, 1]),
                           start: CGPoint(x: plate.midX, y: plate.maxY), end: CGPoint(x: plate.midX, y: plate.minY), options: [])
    let sheen = CGPoint(x: plate.minX + 180 * k, y: plate.maxY - 120 * k)
    ctx.drawRadialGradient(gradient([gray(1, 0.65), gray(1, 0)], [0, 1]), startCenter: sheen, startRadius: 0,
                           endCenter: sheen, endRadius: 520 * k, options: [])
    ctx.restoreGState()
    // Bevel: bright inner rim, crisp outer edge
    ctx.addPath(CGPath(roundedRect: plate.insetBy(dx: 5 * k, dy: 5 * k), cornerWidth: 180 * k, cornerHeight: 180 * k, transform: nil))
    ctx.setStrokeColor(gray(1, 0.95))
    ctx.setLineWidth(6 * k)
    ctx.strokePath()
    ctx.addPath(path)
    ctx.setStrokeColor(gray(0.50))
    ctx.setLineWidth(3 * k)
    ctx.strokePath()

    // Groove between the switch plate and the stamp plate
    let gx = plate.minX + plate.width * 0.355
    ctx.setStrokeColor(gray(0.56))
    ctx.setLineWidth(5 * k)
    ctx.move(to: CGPoint(x: gx, y: plate.minY + 3 * k)); ctx.addLine(to: CGPoint(x: gx, y: plate.maxY - 3 * k)); ctx.strokePath()
    ctx.setStrokeColor(gray(1))
    ctx.setLineWidth(4 * k)
    ctx.move(to: CGPoint(x: gx + 4.5 * k, y: plate.minY + 3 * k)); ctx.addLine(to: CGPoint(x: gx + 4.5 * k, y: plate.maxY - 3 * k)); ctx.strokePath()

    // Toggle switch: recessed slot and a lever in the "up" position, sharp outlines
    let sc = CGPoint(x: (plate.minX + gx) / 2 + 4 * k, y: plate.midY)
    let slot = CGRect(x: sc.x - 58 * k, y: sc.y - 128 * k, width: 116 * k, height: 256 * k)
    let slotPath = CGPath(roundedRect: slot, cornerWidth: 18 * k, cornerHeight: 18 * k, transform: nil)
    ctx.addPath(CGPath(roundedRect: slot.insetBy(dx: -5 * k, dy: -5 * k), cornerWidth: 22 * k, cornerHeight: 22 * k, transform: nil))
    ctx.setStrokeColor(gray(1, 0.95))
    ctx.setLineWidth(4 * k)
    ctx.strokePath()
    ctx.saveGState()
    ctx.addPath(slotPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([gray(0.38), gray(0.60), gray(0.80)], [0, 0.4, 1]),
                           start: CGPoint(x: slot.midX, y: slot.maxY), end: CGPoint(x: slot.midX, y: slot.minY), options: [])
    ctx.restoreGState()
    ctx.addPath(slotPath)
    ctx.setStrokeColor(gray(0.25))
    ctx.setLineWidth(3.2 * k)
    ctx.strokePath()
    let lever = CGRect(x: sc.x - 38 * k, y: sc.y - 8 * k, width: 76 * k, height: 150 * k)
    let leverPath = CGPath(roundedRect: lever, cornerWidth: 14 * k, cornerHeight: 14 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26 * k), blur: 22 * k, color: gray(0, 0.55))
    ctx.addPath(leverPath)
    ctx.setFillColor(gray(0.93))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(leverPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([gray(1), gray(0.93), gray(0.68)], [0, 0.45, 1]),
                           start: CGPoint(x: lever.minX, y: lever.midY), end: CGPoint(x: lever.maxX, y: lever.midY), options: [])
    ctx.drawLinearGradient(gradient([gray(1, 0.9), gray(1, 0)], [0, 1]),
                           start: CGPoint(x: lever.midX, y: lever.maxY), end: CGPoint(x: lever.midX, y: lever.maxY - 40 * k), options: [])
    ctx.restoreGState()
    ctx.addPath(leverPath)
    ctx.setStrokeColor(gray(0.28))
    ctx.setLineWidth(3.2 * k)
    ctx.strokePath()

    let r: CGFloat = 25 * k
    screw(ctx, CGPoint(x: sc.x, y: plate.maxY - 108 * k), r, angle: 0, k: k)
    screw(ctx, CGPoint(x: sc.x, y: plate.minY + 108 * k), r, angle: 0, k: k)
    screw(ctx, CGPoint(x: plate.maxX - 120 * k, y: plate.maxY - 120 * k), r, angle: .pi / 4, k: k)
    screw(ctx, CGPoint(x: plate.maxX - 120 * k, y: plate.minY + 120 * k), r, angle: -.pi / 4, k: k)
    return (plate, gx)
}

/// Pressed into the plastic: a darker floor, a shadow along the upper edge
/// (cast by the cut), a lit lower lip, and the finger lines pressed in.
func drawPress(_ ctx: CGContext, box: CGRect, k: CGFloat) {
    let flat = shape(handFlat, size: box.size)
    let lines = shape(handLines, size: box.size)
    // Lit lower lip
    ctx.saveGState()
    ctx.clip(to: box.offsetBy(dx: 0, dy: -4 * k), mask: flat.gray)
    ctx.setFillColor(gray(1))
    ctx.fill(box.offsetBy(dx: 0, dy: -4 * k))
    ctx.restoreGState()
    // Floor
    ctx.saveGState()
    ctx.clip(to: box, mask: flat.gray)
    ctx.drawLinearGradient(gradient([gray(0.66), gray(0.79)], [0, 1]),
                           start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
    // Inner shadow: the plate around the cut casts a shadow down into it
    let outside = rgbaContext(Int(box.width), Int(box.height))
    outside.setFillColor(gray(0))
    outside.fill(CGRect(x: 0, y: 0, width: box.width, height: box.height))
    outside.setBlendMode(.destinationOut)
    outside.draw(flat.white, in: CGRect(x: 0, y: 0, width: box.width, height: box.height))
    ctx.setShadow(offset: CGSize(width: 0, height: -7 * k), blur: 11 * k, color: gray(0, 0.8))
    ctx.draw(outside.makeImage()!, in: box)
    ctx.restoreGState()
    // Finger lines
    ctx.saveGState()
    ctx.clip(to: box, mask: lines.gray)
    ctx.setFillColor(gray(0.30, 0.6))
    ctx.fill(box)
    ctx.restoreGState()
}

/// A rubber stamp: a ring with the app name and the hand in the middle, in ink, a little worn.
func drawInk(_ ctx: CGContext, box: CGRect, k: CGFloat) {
    let ink = CGColor(red: 0.70, green: 0.09, blue: 0.11, alpha: 0.95)
    let c = CGPoint(x: box.midX, y: box.midY), R = box.width / 2
    let layer = rgbaContext(ctx.width, ctx.height)
    layer.setStrokeColor(ink)
    layer.setFillColor(ink)
    layer.setLineWidth(11 * k)
    layer.strokeEllipse(in: CGRect(x: c.x - R + 6 * k, y: c.y - R + 6 * k, width: 2 * R - 12 * k, height: 2 * R - 12 * k))
    let inner = R - 70 * k
    layer.setLineWidth(5 * k)
    layer.strokeEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner))
    // Text around the ring, centered at the top
    let text = Array("MACTWEAK ★ MACTWEAK ★ ")
    let font = NSFont.systemFont(ofSize: 38 * k, weight: .black)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: ink)!]
    let radius = R - 40 * k
    let widths = text.map { (String($0) as NSString).size(withAttributes: attrs).width + 3 * k }
    let total = widths.reduce(0, +)
    let scale = (2 * .pi * radius) / total  // spread the text over the full circle
    var angle = CGFloat.pi / 2
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: layer, flipped: false)
    for (ch, cw) in zip(text, widths) {
        let step = cw * scale / radius
        let a = angle - step / 2
        layer.saveGState()
        layer.translateBy(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
        layer.rotate(by: a - .pi / 2)
        let gw = (String(ch) as NSString).size(withAttributes: attrs).width
        (String(ch) as NSString).draw(at: CGPoint(x: -gw / 2, y: -font.capHeight / 2), withAttributes: attrs)
        layer.restoreGState()
        angle -= step
    }
    NSGraphicsContext.restoreGraphicsState()
    // Hand line art
    let hs = inner * 1.5
    let hb = CGRect(x: c.x - hs / 2, y: c.y - hs / 2, width: hs, height: hs)
    layer.saveGState()
    layer.clip(to: hb, mask: shape(handLines, size: hb.size).gray)
    layer.fill(hb)
    layer.restoreGState()
    // Wear: knock out speckles (fixed seed so every size looks the same)
    layer.setBlendMode(.destinationOut)
    var seed: UInt64 = 0x5EED
    func rnd() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
    }
    for _ in 0..<1400 {
        let x = c.x - R + rnd() * 2 * R, y = c.y - R + rnd() * 2 * R
        let d = (1 + rnd() * 5) * k
        layer.setFillColor(gray(0, 0.3 + rnd() * 0.6))
        layer.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
    }
    ctx.saveGState()
    ctx.setBlendMode(.multiply)
    ctx.draw(layer.makeImage()!, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    ctx.restoreGState()
}

func draw(_ size: Int) -> Data {
    let k = CGFloat(size) / 1024
    let ctx = rgbaContext(size, size)
    ctx.interpolationQuality = .high
    let (plate, gx) = drawPlate(ctx, k: k)
    let area = CGRect(x: gx + 36 * k, y: plate.minY + 150 * k, width: plate.maxX - gx - 100 * k, height: plate.height - 300 * k)
    let side = min(area.width, area.height)
    let box = CGRect(x: area.midX - side / 2, y: area.midY - side / 2, width: side, height: side).integral
    if style == "ink" { drawInk(ctx, box: box, k: k) } else { drawPress(ctx, box: box, k: k) }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                     ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(size).write(to: URL(fileURLWithPath: "\(output)/icon_\(name).png"))
}
