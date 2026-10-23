import AppKit

// Finder draws the real, draggable icons over this background.
let size = NSSize(width: 640, height: 400)
func render(scale: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640 * scale, pixelsHigh: 400 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let bounds = NSRect(origin: .zero, size: size)
    NSGradient(starting: NSColor(calibratedRed: 0.95, green: 0.965, blue: 0.99, alpha: 1),
               ending: NSColor(calibratedWhite: 0.99, alpha: 1))!.draw(in: bounds, angle: -90)

    func text(_ value: String, top: CGFloat, height: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (value as NSString).draw(in: NSRect(x: 24, y: size.height - top - height, width: 592, height: height),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    text("安装 PluginShelf", top: 35, height: 36, font: .systemFont(ofSize: 27, weight: .semibold),
         color: NSColor(calibratedWhite: 0.15, alpha: 1))
    text("将左侧应用拖入右侧文件夹，即可安装", top: 82, height: 24,
         font: .systemFont(ofSize: 15), color: NSColor(calibratedWhite: 0.39, alpha: 1))

    // Restrained directional cue, aligned with the two native Finder icons.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 286, y: 220))
    arrow.line(to: NSPoint(x: 353, y: 220))
    arrow.move(to: NSPoint(x: 342, y: 231))
    arrow.line(to: NSPoint(x: 353, y: 220))
    arrow.line(to: NSPoint(x: 342, y: 209))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(calibratedRed: 0.32, green: 0.43, blue: 0.73, alpha: 0.8).setStroke()
    arrow.stroke()

    text("复制完成后，从「应用程序」打开 PluginShelf", top: 341, height: 22,
         font: .systemFont(ofSize: 12), color: NSColor(calibratedWhite: 0.48, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let normal = render(scale: 1)
let retina = render(scale: 2)
try NSBitmapImageRep.representationOfImageReps(in: [normal, retina], using: .tiff, properties: [.compressionFactor: 0.8])!
    .write(to: destination)
try retina.representation(using: .png, properties: [:])!.write(to: destination.deletingPathExtension().appendingPathExtension("png"))
