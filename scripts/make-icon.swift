import AppKit

// Renders the app icon: macOS squircle, teal gradient, white SF Symbol "hand.tap".
// Output: 1024 px PNG. Usage: make-icon <out.png>
let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

func squirclePath(in rect: CGRect) -> NSBezierPath {
    // Continuous-corner approximation used by macOS icon templates (radius ≈ 22.4%).
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.224, yRadius: rect.height * 0.224)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
let cg = context.cgContext
cg.clear(CGRect(x: 0, y: 0, width: size, height: size))

// Icon body occupies the standard 824/1024 grid, leaving room for the system shadow.
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = squirclePath(in: body)

// Soft drop shadow.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: NSColor.black.withAlphaComponent(0.28).cgColor)
NSColor(calibratedRed: 0.20, green: 0.60, blue: 0.50, alpha: 1).setFill()
squircle.fill()
cg.restoreGState()

// Diagonal teal gradient.
cg.saveGState()
squircle.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.50, blue: 0.44, alpha: 1),
    NSColor(calibratedRed: 0.23, green: 0.66, blue: 0.54, alpha: 1),
    NSColor(calibratedRed: 0.36, green: 0.78, blue: 0.64, alpha: 1)
])!
gradient.draw(in: body, angle: 60)
// Gentle top highlight across the whole body, no seam.
let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0.16)])!
highlight.draw(in: body, angle: 90)
cg.restoreGState()

// White hand.tap symbol with a soft shadow.
let configuration = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let symbol = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
    FileHandle.standardError.write("hand.tap symbol unavailable\n".data(using: .utf8)!)
    exit(1)
}
symbol.isTemplate = false
let symbolSize = symbol.size
let scale = min(body.width * 0.66 / symbolSize.width, body.height * 0.66 / symbolSize.height)
let drawn = CGSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
let origin = CGPoint(x: body.midX - drawn.width / 2, y: body.midY - drawn.height / 2 - size * 0.015)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.30).cgColor)
symbol.draw(in: CGRect(origin: origin, size: drawn), from: .zero, operation: .sourceOver, fraction: 1)
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output) (\(symbolSize.width)x\(symbolSize.height) symbol source)")
