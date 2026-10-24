import AppKit

// Native tile composition in a 1024-point space with a generated library foreground.
// Usage: render-icon <destination.png> <pixel-size> <foreground.png>
guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(Data("Usage: render-icon <destination.png> <pixel-size> <foreground.png>\n".utf8))
    exit(2)
}
let pixels = Int(CommandLine.arguments[2]) ?? 1024
guard (16...4096).contains(pixels),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create icon bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext
context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
context.setShouldAntialias(true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}
func gradient(_ path: NSBezierPath, _ colors: [NSColor], angle: CGFloat = -90) {
    // Every call uses a fixed, nonempty palette.
    NSGradient(colors: colors)!.draw(in: path, angle: angle)
}
func stroke(_ path: NSBezierPath, _ tint: NSColor, _ width: CGFloat) {
    path.lineWidth = width
    tint.setStroke()
    path.stroke()
}
func shadowed(tint: NSColor, blur: CGFloat, offset: NSSize, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = tint
    // NSShadow uses device-space lengths; scale these alongside the artwork.
    let scale = CGFloat(pixels) / 1024
    shadow.shadowBlurRadius = blur * scale
    shadow.shadowOffset = NSSize(width: offset.width * scale, height: offset.height * scale)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

// 82.8% base width: the previous 88.7% dominated neighbouring icons.
let base = rounded(NSRect(x: 88, y: 88, width: 848, height: 848), 190)
shadowed(tint: color(0x071C49, 0.23), blur: 17, offset: NSSize(width: 0, height: -9)) {
    color(0x0877EE).setFill()
    base.fill()
}
gradient(base, [color(0x39C8E7), color(0x149CF5), color(0x0753E9)], angle: -83)
NSGraphicsContext.saveGraphicsState()
base.addClip()
NSGradient(starting: color(0xCAFFFF, 0.20), ending: color(0x70F3FF, 0))!
    .draw(fromCenter: NSPoint(x: 280, y: 890), radius: 0,
          toCenter: NSPoint(x: 280, y: 890), radius: 850,
          options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
NSGraphicsContext.restoreGraphicsState()
if pixels >= 64 {
    stroke(rounded(NSRect(x: 89.5, y: 89.5, width: 845, height: 845), 188.5), color(0xD9FFFF, 0.34), 2)
}

// A separate foreground: varied audio plug-in books held together on one shelf.
// The existing tile geometry and artwork placement remain deterministic.
guard let artwork = NSImage(contentsOfFile: CommandLine.arguments[3]) else {
    FileHandle.standardError.write(Data("Unable to load library artwork.\n".utf8))
    exit(3)
}
graphics.imageInterpolation = .high
artwork.draw(in: NSRect(x: 112, y: 112, width: 800, height: 800),
          from: NSRect(origin: .zero, size: artwork.size), operation: .sourceOver, fraction: 1)

NSGraphicsContext.restoreGraphicsState()
let export = bitmap.converting(to: .sRGB, renderingIntent: .default) ?? bitmap
guard let png = export.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
