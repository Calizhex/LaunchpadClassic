// Generuje ikonę aplikacji (PNG 1024×1024). Użycie: swift MakeIcon.swift <plik.png>
import AppKit

let size = 1024
guard CommandLine.arguments.count > 1,
      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fputs("Użycie: swift MakeIcon.swift <plik.png>\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let base = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.27, blue: 0.38, alpha: 1),
           ending: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.13, alpha: 1))?.draw(in: base, angle: -90)

let colors: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow,
    .systemGreen, .systemTeal, .systemBlue,
    .systemIndigo, .systemPurple, .systemPink,
]
let tile: CGFloat = 180
let gap: CGFloat = 52
let start = rect.minX + (rect.width - (tile * 3 + gap * 2)) / 2
for i in 0..<9 {
    let col = CGFloat(i % 3)
    let row = CGFloat(2 - i / 3)
    let r = NSRect(x: start + col * (tile + gap), y: start + row * (tile + gap), width: tile, height: tile)
    let path = NSBezierPath(roundedRect: r, xRadius: 44, yRadius: 44)
    let c = colors[i].usingColorSpace(.deviceRGB) ?? colors[i]
    NSGradient(starting: c.blended(withFraction: 0.35, of: .white) ?? c, ending: c)?.draw(in: path, angle: -90)
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
