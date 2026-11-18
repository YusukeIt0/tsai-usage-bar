// Builds Resources/AppIcon.icns from Resources/icon/surf-rabbit.png.
//   swift scripts/make-icon.swift
// macOS icon grid: 1024 canvas, 824 pt rounded-square body, soft shadow.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let art = NSImage(contentsOf: root.appendingPathComponent("Resources/icon/surf-rabbit.png"))!
let out = root.appendingPathComponent("Resources/icon/AppIcon-1024.png")

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Soft drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
color(0x8FCDE3).setFill()
shape.fill()
ctx.restoreGState()

// Sky-to-sea gradient.
ctx.saveGState()
shape.addClip()
NSGradient(colors: [color(0xEAF6FB), color(0xBFE4F1), color(0x7DC2DC)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: -90)
// A gentle wave band behind the board.
let wave = NSBezierPath()
wave.move(to: CGPoint(x: 100, y: 330))
wave.curve(to: CGPoint(x: 512, y: 300), controlPoint1: CGPoint(x: 230, y: 390), controlPoint2: CGPoint(x: 380, y: 250))
wave.curve(to: CGPoint(x: 924, y: 340), controlPoint1: CGPoint(x: 650, y: 350), controlPoint2: CGPoint(x: 800, y: 400))
wave.line(to: CGPoint(x: 924, y: 100))
wave.line(to: CGPoint(x: 100, y: 100))
wave.close()
color(0x5FB0D0).withAlphaComponent(0.55).setFill()
wave.fill()
ctx.restoreGState()

// The rabbit, centered and slightly lifted.
let artSize = art.size
let maxW: CGFloat = 640, maxH: CGFloat = 600
let scale = min(maxW / artSize.width, maxH / artSize.height)
let w = artSize.width * scale, h = artSize.height * scale
art.draw(in: CGRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - h) / 2 + 10, width: w, height: h))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")

// Iconset and .icns (sizes macOS uses), via sips and iconutil.
let iconset = root.appendingPathComponent("Resources/icon/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func run(_ tool: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
}
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    run("/usr/bin/sips", ["-z", "\(px)", "\(px)", out.path, "--out", iconset.appendingPathComponent("icon_\(name).png").path])
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path])
try? FileManager.default.removeItem(at: iconset)
print("wrote Resources/AppIcon.icns")
