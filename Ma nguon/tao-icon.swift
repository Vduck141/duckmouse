import AppKit
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let r = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: r, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 1.0, green: 0.86, blue: 0.20, alpha: 1), NSColor(red: 0.98, green: 0.70, blue: 0.05, alpha: 1)])!
    .draw(in: path, angle: -90)
let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
    .applying(.init(paletteColors: [.black]))
if let sym = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let s = sym.size
    sym.draw(in: NSRect(x: (S - s.width) / 2, y: (S - s.height) / 2 + 10, width: s.width, height: s.height))
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
