import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.28, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: bounds.insetBy(dx: CGFloat(pixels) * 0.05, dy: CGFloat(pixels) * 0.05),
      xRadius: CGFloat(pixels) * 0.21, yRadius: CGFloat(pixels) * 0.21
    ).fill()
    for (i, alpha) in [0.4, 1.0, 0.65].enumerated() {
      NSColor.white.withAlphaComponent(alpha).setFill()
      let x = CGFloat(pixels) * (0.19 + Double(i) * 0.225)
      NSBezierPath(
        roundedRect: NSRect(
          x: x, y: CGFloat(pixels) * 0.23,
          width: CGFloat(pixels) * 0.18, height: CGFloat(pixels) * 0.54),
        xRadius: CGFloat(pixels) * 0.035, yRadius: CGFloat(pixels) * 0.035
      ).fill()
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: directory.appendingPathComponent(filename))
  }
}
