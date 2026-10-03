// Draws the syncR app icon (two speakers) and writes Resources/AppIcon.icns.
//   swift Resources/make-icon.swift
import AppKit

func draw(_ size: CGFloat) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = size / 1024
  // macOS icon grid: 824 pt rounded square centered on a 1024 canvas
  let bg = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
  NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.42, alpha: 1),
                      NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.14, alpha: 1)])!.draw(in: bg, angle: -90)
  // two speakers, the second one behind and offset (like the menu bar symbol)
  let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.42, alpha: 1),
                                     NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.14, alpha: 1)])!
  let cone = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.26, alpha: 1)
  func speaker(_ r: NSRect, _ body: NSColor) {
    body.setFill(); NSBezierPath(roundedRect: r, xRadius: r.width * 0.2, yRadius: r.width * 0.2).fill()
    let cx = r.midX
    let wr = r.width * 0.34, wy = r.minY + r.height * 0.33
    cone.setFill(); NSBezierPath(ovalIn: NSRect(x: cx - wr, y: wy - wr, width: 2 * wr, height: 2 * wr)).fill()
    body.setFill(); NSBezierPath(ovalIn: NSRect(x: cx - wr * 0.3, y: wy - wr * 0.3, width: 0.6 * wr, height: 0.6 * wr)).fill()
    let tr = r.width * 0.16, ty = r.minY + r.height * 0.76
    cone.setFill(); NSBezierPath(ovalIn: NSRect(x: cx - tr, y: ty - tr, width: 2 * tr, height: 2 * tr)).fill()
  }
  let back = NSRect(x: 297 * s, y: 312 * s, width: 260 * s, height: 490 * s)
  let front = NSRect(x: 467 * s, y: 222 * s, width: 260 * s, height: 490 * s)
  speaker(back, NSColor(calibratedWhite: 0.96, alpha: 0.55))
  // gap around the front speaker: repaint the background there
  let gap = 26 * s
  NSGraphicsContext.saveGraphicsState()
  NSBezierPath(roundedRect: front.insetBy(dx: -gap, dy: -gap), xRadius: front.width * 0.2 + gap, yRadius: front.width * 0.2 + gap).addClip()
  gradient.draw(in: bg, angle: -90)
  NSGraphicsContext.restoreGraphicsState()
  speaker(front, NSColor(calibratedWhite: 0.96, alpha: 1))
  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = dir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let px = CGFloat(base * scale)
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try! draw(px).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
  }
}
try! draw(1024).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("AppIcon-preview.png"))
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("written: \(dir.path)/AppIcon.icns")
