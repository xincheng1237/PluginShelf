import AppKit
let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let bounds = NSRect(x: 58, y: 58, width: 908, height: 908)
let path = NSBezierPath(roundedRect: bounds, xRadius: 205, yRadius: 205)
NSColor(calibratedWhite: 0.06, alpha: 0.18).setFill()
let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.22); shadow.shadowOffset = NSSize(width: 0, height: -15); shadow.shadowBlurRadius = 32
shadow.set(); path.fill(); NSShadow().set()
NSGradient(colors: [NSColor(calibratedRed: 0.32, green: 0.47, blue: 0.96, alpha: 1), NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.68, alpha: 1)])!.draw(in: path, angle: -75)
let shelf = NSBezierPath(roundedRect: NSRect(x: 235, y: 230, width: 554, height: 564), xRadius: 65, yRadius: 65)
shelf.lineWidth = 19; NSColor.white.withAlphaComponent(0.9).setStroke(); shelf.stroke()
for y in [375.0, 525.0, 675.0] {
    let line = NSBezierPath(); line.move(to: NSPoint(x: 275, y: y)); line.line(to: NSPoint(x: 749, y: y)); line.lineWidth = 12; NSColor.white.withAlphaComponent(0.35).setStroke(); line.stroke()
}
let waveform = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 240, weight: .medium))!
let white = NSImage(size: waveform.size); white.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: white.size).fill(); waveform.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1); white.unlockFocus()
NSColor(calibratedRed: 0.25, green: 0.36, blue: 0.82, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 315, y: 355, width: 394, height: 290), xRadius: 45, yRadius: 45).fill()
white.draw(in: NSRect(x: 355, y: 390, width: 314, height: 220))
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
