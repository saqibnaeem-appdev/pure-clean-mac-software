#!/usr/bin/env swift
// Generates PureClean's app icon (shield = safe, sparkle = clean) at every
// macOS size and writes the AppIcon.appiconset. Vector-drawn, re-rendered
// crisply per size. Run:  swift make-icon.swift
import AppKit

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// Renders the icon into a CGContext of the given pixel size.
func draw(_ ctx: CGContext, _ size: CGFloat) {
    let s = size
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // 1) Squircle background with a diagonal blue→purple→pink gradient.
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.2237                     // macOS "continuous" corner
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()

    let colors = [
        CGColor(red: 0.16, green: 0.38, blue: 0.98, alpha: 1),   // blue
        CGColor(red: 0.55, green: 0.31, blue: 0.96, alpha: 1),   // purple
        CGColor(red: 0.93, green: 0.29, blue: 0.60, alpha: 1),   // pink
    ]
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // Soft top-left sheen for depth.
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(gray: 1, alpha: 0.28), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(sheen,
                           startCenter: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY - rect.height * 0.25),
                           startRadius: 0,
                           endCenter: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY - rect.height * 0.25),
                           endRadius: rect.width * 0.7, options: [])
    ctx.restoreGState()

    // 2) Shield (safety). Centered, drawn in translucent white.
    let cx = s * 0.5
    let top = s * 0.30, bottom = s * 0.76
    let halfW = s * 0.205
    let shoulder = s * 0.40
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: cx, y: top))
    shield.addLine(to: CGPoint(x: cx + halfW, y: top + (shoulder - top) * 0.35))
    shield.addLine(to: CGPoint(x: cx + halfW, y: shoulder))
    // Curve down to the point.
    shield.addCurve(to: CGPoint(x: cx, y: bottom),
                    control1: CGPoint(x: cx + halfW, y: bottom - (bottom - shoulder) * 0.35),
                    control2: CGPoint(x: cx + halfW * 0.55, y: bottom - (bottom - shoulder) * 0.05))
    shield.addCurve(to: CGPoint(x: cx - halfW, y: shoulder),
                    control1: CGPoint(x: cx - halfW * 0.55, y: bottom - (bottom - shoulder) * 0.05),
                    control2: CGPoint(x: cx - halfW, y: bottom - (bottom - shoulder) * 0.35))
    shield.addLine(to: CGPoint(x: cx - halfW, y: top + (shoulder - top) * 0.35))
    shield.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(gray: 0, alpha: 0.25))
    ctx.addPath(shield)
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.18))
    ctx.fillPath()
    ctx.restoreGState()

    // Shield rim.
    ctx.addPath(shield)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
    ctx.setLineWidth(s * 0.018)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // 3) Four-point sparkle (the brand mark = clean/fresh) inside the shield.
    func sparkle(center: CGPoint, radius r: CGFloat, alpha: CGFloat) {
        let waist = r * 0.30
        let p = CGMutablePath()
        p.move(to: CGPoint(x: center.x, y: center.y + r))
        p.addQuadCurve(to: CGPoint(x: center.x + r, y: center.y),
                       control: CGPoint(x: center.x + waist, y: center.y + waist))
        p.addQuadCurve(to: CGPoint(x: center.x, y: center.y - r),
                       control: CGPoint(x: center.x + waist, y: center.y - waist))
        p.addQuadCurve(to: CGPoint(x: center.x - r, y: center.y),
                       control: CGPoint(x: center.x - waist, y: center.y - waist))
        p.addQuadCurve(to: CGPoint(x: center.x, y: center.y + r),
                       control: CGPoint(x: center.x - waist, y: center.y + waist))
        p.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * 0.5, color: CGColor(gray: 1, alpha: 0.8))
        ctx.addPath(p)
        ctx.setFillColor(CGColor(gray: 1, alpha: alpha))
        ctx.fillPath()
        ctx.restoreGState()
    }
    let heroCenter = CGPoint(x: cx, y: lerp(top, bottom, 0.46))
    sparkle(center: heroCenter, radius: s * 0.135, alpha: 1)
    sparkle(center: CGPoint(x: cx + s * 0.10, y: heroCenter.y + s * 0.10), radius: s * 0.045, alpha: 0.95)
    sparkle(center: CGPoint(x: cx - s * 0.095, y: heroCenter.y - s * 0.085), radius: s * 0.035, alpha: 0.9)
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext, CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// AppIcon.appiconset layout.
let dir = "PureClean/Resources/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

struct Entry { let size: Int; let scale: Int }
let entries = [Entry(size:16,scale:1),Entry(size:16,scale:2),Entry(size:32,scale:1),Entry(size:32,scale:2),
               Entry(size:128,scale:1),Entry(size:128,scale:2),Entry(size:256,scale:1),Entry(size:256,scale:2),
               Entry(size:512,scale:1),Entry(size:512,scale:2)]

var images: [String] = []
for e in entries {
    let px = e.size * e.scale
    let name = "icon_\(e.size)x\(e.size)\(e.scale == 2 ? "@2x" : "").png"
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
    images.append("""
        { "size":"\(e.size)x\(e.size)", "idiom":"mac", "filename":"\(name)", "scale":"\(e.scale)x" }
    """)
}

let contents = """
{
  "images": [
\(images.joined(separator: ",\n"))
  ],
  "info": { "version": 1, "author": "xcode" }
}
"""
try! contents.write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
print("✓ Icon set written to \(dir)")
