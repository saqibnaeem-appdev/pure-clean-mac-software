#!/usr/bin/env swift
// Renders the DMG installer background as a vector PDF (Finder rasterizes
// PDFs at the display scale, so it stays Retina-sharp on macOS Tahoe, which
// draws raster backgrounds at raw pixel size) plus PNG previews.
// Layout matches build-dmg.sh: icons at x=165/x=495, centered y≈195.
// Run:  swift make-dmg-background.swift <outdir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/dmg-assets"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Logical canvas (points). Window content is exactly this size.
let logicalW: CGFloat = 660
let logicalH: CGFloat = 440

// CG coordinates are bottom-up: cgY = logicalH - finderY.
func draw(_ ctx: CGContext, scale: CGFloat) {
    ctx.scaleBy(x: scale, y: scale)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Clean, near-white field: a whisper of lavender at the bottom so the
    // window doesn't feel sterile, but every label stays high-contrast.
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [
                            CGColor(red: 0.99, green: 0.99, blue: 1.00, alpha: 1),
                            CGColor(red: 0.955, green: 0.955, blue: 0.985, alpha: 1),
                        ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: logicalH),
                           end: CGPoint(x: 0, y: 0), options: [])

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    func text(_ string: String, font: NSFont, color: NSColor, center: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = string.size(withAttributes: attrs)
        string.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                    withAttributes: attrs)
    }

    // Sparkle mark + wordmark, top center (Finder y≈58).
    let markCenter = CGPoint(x: logicalW / 2 - 82, y: 382)
    let markPath = CGMutablePath()
    let r: CGFloat = 14, waist: CGFloat = 14 * 0.3
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

    text("PureClean", font: NSFont.systemFont(ofSize: 32, weight: .bold),
         color: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.22, alpha: 1),
         center: CGPoint(x: logicalW / 2 + 18, y: 382))
    text("Safe cleaning & live system monitoring for your Mac",
         font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
         color: NSColor(calibratedWhite: 0.35, alpha: 1),
         center: CGPoint(x: logicalW / 2, y: 346))

    // Drag arrow between the icon wells (Finder y=195 → CG y=245).
    let arrowY: CGFloat = 245
    let endX: CGFloat = 402
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 0.45, green: 0.42, blue: 0.85, alpha: 0.55))
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [1, 12])
    ctx.move(to: CGPoint(x: 258, y: arrowY))
    ctx.addLine(to: CGPoint(x: endX - 18, y: arrowY))
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    let head = CGMutablePath()
    head.move(to: CGPoint(x: endX - 20, y: arrowY + 11))
    head.addLine(to: CGPoint(x: endX, y: arrowY))
    head.addLine(to: CGPoint(x: endX - 20, y: arrowY - 11))
    ctx.addPath(head)
    ctx.setFillColor(CGColor(red: 0.45, green: 0.42, blue: 0.85, alpha: 0.55))
    ctx.fillPath()
    ctx.restoreGState()

    // Caption well below the icon labels (Finder y≈336).
    text("Drag PureClean into Applications to install",
         font: NSFont.systemFont(ofSize: 13, weight: .semibold),
         color: NSColor(calibratedWhite: 0.30, alpha: 1),
         center: CGPoint(x: logicalW / 2, y: 104))

    // Brand signature: gradient-filled company name, centered.
    gradientText(ctx, "AWS NextGen IT",
                 font: NSFont.systemFont(ofSize: 16, weight: .bold),
                 center: CGPoint(x: logicalW / 2, y: 54))
    text("© 2026 AWS NextGen IT LTD · Premium Mac utilities",
         font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
         color: NSColor(calibratedWhite: 0.55, alpha: 1),
         center: CGPoint(x: logicalW / 2, y: 30))

    NSGraphicsContext.restoreGraphicsState()
}

/// Draws text filled with the blue→purple brand gradient.
func gradientText(_ ctx: CGContext, _ string: String, font: NSFont, center: CGPoint) {
    let attributed = NSAttributedString(string: string, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

    ctx.saveGState()
    ctx.textPosition = CGPoint(x: center.x - width / 2, y: center.y - font.capHeight / 2)
    ctx.setTextDrawingMode(.clip)
    CTLineDraw(line, ctx)
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [
                                  CGColor(red: 0.16, green: 0.38, blue: 0.98, alpha: 1),
                                  CGColor(red: 0.58, green: 0.30, blue: 0.96, alpha: 1),
                              ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: center.x - width / 2, y: center.y),
                           end: CGPoint(x: center.x + width / 2, y: center.y), options: [])
    ctx.restoreGState()
}

// Vector PDF — the shipping background.
var mediaBox = CGRect(x: 0, y: 0, width: logicalW, height: logicalH)
let pdfURL = URL(fileURLWithPath: "\(outDir)/background.pdf")
let pdf = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil)!
pdf.beginPDFPage(nil)
draw(pdf, scale: 1)
pdf.endPDFPage()
pdf.closePDF()

// PNG preview (1x) for quick visual checks.
func renderPNG(scale: CGFloat) -> Data {
    let w = Int(logicalW * scale), h = Int(logicalH * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: logicalW, height: logicalH)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext, scale: scale)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
try! renderPNG(scale: 1).write(to: URL(fileURLWithPath: "\(outDir)/background.png"))
print("✓ DMG background (PDF + PNG preview) written to \(outDir)")
