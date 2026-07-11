#!/usr/bin/env swift
// Renders the DMG installer background (1x + 2x) — a soft branded gradient,
// the PureClean mark, and a drag-to-Applications arrow aligned with the
// icon positions set by build-dmg.sh. Run:  swift make-dmg-background.swift <outdir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/dmg-assets"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Logical canvas: 660×400. Icons sit at x=165 and x=495, centered y≈200.
let logicalW: CGFloat = 660
let logicalH: CGFloat = 400

func draw(_ ctx: CGContext, scale: CGFloat) {
    ctx.scaleBy(x: scale, y: scale)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: logicalW, height: logicalH)

    // Soft vertical wash, near-white to pale blue.
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [
                            CGColor(red: 0.97, green: 0.97, blue: 1.00, alpha: 1),
                            CGColor(red: 0.90, green: 0.92, blue: 0.99, alpha: 1),
                        ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: logicalH),
                           end: CGPoint(x: 0, y: 0), options: [])

    // Two faint brand glows.
    func glow(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [color, CGColor(gray: 1, alpha: 0)] as CFArray,
                                  locations: [0, 1])!
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: radius, options: [])
    }
    glow(CGPoint(x: 110, y: 340), 260, CGColor(red: 0.30, green: 0.45, blue: 0.98, alpha: 0.13))
    glow(CGPoint(x: 560, y: 60), 240, CGColor(red: 0.60, green: 0.35, blue: 0.95, alpha: 0.12))

    // Wordmark, top center.
    func text(_ string: String, font: NSFont, color: NSColor, center: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = string.size(withAttributes: attrs)
        string.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                    withAttributes: attrs)
    }

    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.current = ns

    // Sparkle mark next to the wordmark.
    let markCenter = CGPoint(x: logicalW / 2 - 74, y: 342)
    let markPath = CGMutablePath()
    let r: CGFloat = 13, waist: CGFloat = 13 * 0.3
    markPath.move(to: CGPoint(x: markCenter.x, y: markCenter.y + r))
    markPath.addQuadCurve(to: CGPoint(x: markCenter.x + r, y: markCenter.y),
                          control: CGPoint(x: markCenter.x + waist, y: markCenter.y + waist))
    markPath.addQuadCurve(to: CGPoint(x: markCenter.x, y: markCenter.y - r),
                          control: CGPoint(x: markCenter.x + waist, y: markCenter.y - waist))
    markPath.addQuadCurve(to: CGPoint(x: markCenter.x - r, y: markCenter.y),
                          control: CGPoint(x: markCenter.x - waist, y: markCenter.y - waist))
    markPath.addQuadCurve(to: CGPoint(x: markCenter.x, y: markCenter.y + r),
                          control: CGPoint(x: markCenter.x - waist, y: markCenter.y + waist))
    markPath.closeSubpath()
    ctx.saveGState()
    let markGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [
                                      CGColor(red: 0.16, green: 0.38, blue: 0.98, alpha: 1),
                                      CGColor(red: 0.55, green: 0.31, blue: 0.96, alpha: 1),
                                  ] as CFArray, locations: [0, 1])!
    ctx.addPath(markPath)
    ctx.clip()
    ctx.drawLinearGradient(markGradient,
                           start: CGPoint(x: markCenter.x - r, y: markCenter.y + r),
                           end: CGPoint(x: markCenter.x + r, y: markCenter.y - r), options: [])
    ctx.restoreGState()

    text("PureClean", font: NSFont.systemFont(ofSize: 30, weight: .bold),
         color: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.22, alpha: 1),
         center: CGPoint(x: logicalW / 2 + 14, y: 342))
    text("Safe cleaning & live system monitoring for your Mac",
         font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
         color: NSColor(calibratedWhite: 0.35, alpha: 1),
         center: CGPoint(x: logicalW / 2, y: 310))

    // Drag arrow between the two icon slots (icons at x=165 and x=495, y≈200
    // in Finder's flipped coordinates → y≈200 here too since it's centered).
    let arrowY: CGFloat = 200
    let start = CGPoint(x: 250, y: arrowY)
    let end = CGPoint(x: 408, y: arrowY)
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 0.45, green: 0.42, blue: 0.85, alpha: 0.55))
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [1, 12])
    ctx.move(to: start)
    ctx.addLine(to: CGPoint(x: end.x - 18, y: arrowY))
    ctx.strokePath()
    // Arrow head.
    ctx.setLineDash(phase: 0, lengths: [])
    let head = CGMutablePath()
    head.move(to: CGPoint(x: end.x - 20, y: arrowY + 11))
    head.addLine(to: CGPoint(x: end.x, y: arrowY))
    head.addLine(to: CGPoint(x: end.x - 20, y: arrowY - 11))
    ctx.addPath(head)
    ctx.setFillColor(CGColor(red: 0.45, green: 0.42, blue: 0.85, alpha: 0.55))
    ctx.fillPath()
    ctx.restoreGState()

    text("Drag PureClean into Applications to install",
         font: NSFont.systemFont(ofSize: 13, weight: .semibold),
         color: NSColor(calibratedWhite: 0.30, alpha: 1),
         center: CGPoint(x: logicalW / 2, y: 86))
    text("© 2026 AWS NextGen IT LTD",
         font: NSFont.systemFont(ofSize: 10, weight: .regular),
         color: NSColor(calibratedWhite: 0.55, alpha: 1),
         center: CGPoint(x: logicalW / 2, y: 30))

    NSGraphicsContext.restoreGraphicsState()
    _ = rect
}

func render(scale: CGFloat) -> Data {
    let w = Int(logicalW * scale), h = Int(logicalH * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: logicalW, height: logicalH)   // marks 2x as Retina
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext, scale: scale)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: URL(fileURLWithPath: "\(outDir)/background.png"))
try! render(scale: 2).write(to: URL(fileURLWithPath: "\(outDir)/background@2x.png"))
print("✓ DMG background written to \(outDir)")
