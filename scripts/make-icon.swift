import AppKit
import ImageIO

// The Dock icon is compiled from Icon Composer. This exports the menu-bar template.
guard CommandLine.arguments.count == 3 else {
  fatalError("Usage: make-icon.swift input-mark.png output-template.pdf")
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fatalError("The menu-bar mark could not be read.") }
let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
guard
  let bitmap = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo)
else { fatalError("The menu-bar mark could not be decoded.") }
bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
var left = width
var right = 0
var top = height
var bottom = 0
for y in 0..<height {
  for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= 128 {
    left = min(left, x)
    right = max(right, x)
    top = min(top, y)
    bottom = max(bottom, y)
  }
}
guard right > left, bottom > top,
  let normalized = bitmap.makeImage()?.cropping(
    to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
else { fatalError("The menu-bar mark is empty.") }
try FileManager.default.createDirectory(
  at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
var mediaBox = CGRect(x: 0, y: 0, width: 18, height: 18)
guard let pdf = CGContext(output as CFURL, mediaBox: &mediaBox, nil) else {
  fatalError("The menu-bar PDF could not be created.")
}
let scale = min(16 / CGFloat(normalized.width), 16 / CGFloat(normalized.height))
let size = CGSize(
  width: CGFloat(normalized.width) * scale, height: CGFloat(normalized.height) * scale)
pdf.beginPDFPage(nil)
pdf.draw(
  normalized,
  in: CGRect(
    x: (18 - size.width) / 2, y: (18 - size.height) / 2, width: size.width, height: size.height))
pdf.endPDFPage()
pdf.closePDF()
