#!/usr/bin/env swift
// Generates AppIcon.iconset PNGs: dark rounded square, cream ninja, orange cursor.
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> Data? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                              pixelsWide: Int(size), pixelsHigh: Int(size),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.06
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = size * 0.22

    NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.10, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).fill()

    let cream = NSColor(calibratedRed: 0.984, green: 0.969, blue: 0.933, alpha: 1)
    let ink = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.08, alpha: 1)
    let accent = NSColor(calibratedRed: 1, green: 0.42, blue: 0.21, alpha: 1)

    let head = NSBezierPath(ovalIn: NSRect(
        x: body.minX + body.width * 0.14,
        y: body.minY + body.height * 0.28,
        width: body.width * 0.52,
        height: body.height * 0.50
    ))
    cream.setFill()
    head.fill()

    let mask = NSBezierPath(roundedRect: NSRect(
        x: body.minX + body.width * 0.18,
        y: body.minY + body.height * 0.46,
        width: body.width * 0.44,
        height: body.height * 0.12
    ), xRadius: size * 0.03, yRadius: size * 0.03)
    ink.setFill()
    mask.fill()

    cream.setFill()
    let eye = size * 0.045
    NSBezierPath(ovalIn: NSRect(x: body.minX + body.width * 0.28, y: body.minY + body.height * 0.49, width: eye, height: eye)).fill()
    NSBezierPath(ovalIn: NSRect(x: body.minX + body.width * 0.44, y: body.minY + body.height * 0.49, width: eye, height: eye)).fill()

    // Cursor
    let cursor = NSBezierPath()
    let cx = body.minX + body.width * 0.62
    let cy = body.minY + body.height * 0.18
    let s = body.width
    cursor.move(to: NSPoint(x: cx, y: cy + s * 0.42))
    cursor.line(to: NSPoint(x: cx, y: cy))
    cursor.line(to: NSPoint(x: cx + s * 0.10, y: cy + s * 0.10))
    cursor.line(to: NSPoint(x: cx + s * 0.16, y: cy - s * 0.06))
    cursor.line(to: NSPoint(x: cx + s * 0.22, y: cy - s * 0.02))
    cursor.line(to: NSPoint(x: cx + s * 0.16, y: cy + s * 0.14))
    cursor.line(to: NSPoint(x: cx + s * 0.28, y: cy + s * 0.14))
    cursor.close()
    accent.setFill()
    cursor.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, size) in sizes {
    guard let data = drawIcon(size: size) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).png"))
}
print("wrote iconset to \(outputDir)")
