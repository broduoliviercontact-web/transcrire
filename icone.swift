// Dessine l'icône de Transcrire (des ondes sonores qui deviennent des lignes de texte).
// Utilisé par installer.sh :  icone <sortie.png>
import AppKit

let cote = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cote, pixelsHigh: cote, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Grille des icônes macOS : carré arrondi de 824 px centré dans 1024.
let fond = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.56, green: 0.42, blue: 1.00, alpha: 1),
                    NSColor(red: 0.29, green: 0.24, blue: 0.86, alpha: 1)])!.draw(in: fond, angle: -90)
fond.addClip()
NSGradient(colors: [.white.withAlphaComponent(0.22), .white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)

func barre(_ x: CGFloat, _ y: CGFloat, _ l: CGFloat, _ h: CGFloat, _ alpha: CGFloat) {
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: l, height: h), xRadius: min(l, h) / 2, yRadius: min(l, h) / 2).fill()
}

// ondes (à gauche)
for (i, h) in [150, 300, 430, 270, 140].enumerated() {
    barre(236 + CGFloat(i) * 66, 512 - CGFloat(h) / 2, 42, CGFloat(h), 1)
}
// lignes de texte (à droite)
for (i, l) in [210, 160, 190, 110].enumerated() {
    barre(600, 512 + 105 - CGFloat(i) * 70 - 20, CGFloat(l), 40, 1 - CGFloat(i) * 0.15)
}

try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: CommandLine.arguments[1]))
