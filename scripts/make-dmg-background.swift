import AppKit

let width: CGFloat = 660
let height: CGFloat = 420

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
let cg = context.cgContext

let rect = NSRect(x: 0, y: 0, width: width, height: height)
let background = NSGradient(
    starting: NSColor(srgbRed: 0.988, green: 0.980, blue: 0.961, alpha: 1),
    ending: NSColor(srgbRed: 0.949, green: 0.922, blue: 0.871, alpha: 1)
)!
background.draw(in: rect, angle: -60)

func blob(center: CGPoint, radius: CGFloat, color: NSColor) {
    let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
    let locations: [CGFloat] = [0, 1]
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: locations
    ) else { return }
    cg.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: []
    )
}

blob(
    center: CGPoint(x: 80, y: 370),
    radius: 270,
    color: NSColor(srgbRed: 0.945, green: 0.812, blue: 0.690, alpha: 0.55)
)
blob(
    center: CGPoint(x: 600, y: 330),
    radius: 230,
    color: NSColor(srgbRed: 0.902, green: 0.753, blue: 0.682, alpha: 0.38)
)
blob(
    center: CGPoint(x: 540, y: 60),
    radius: 250,
    color: NSColor(srgbRed: 0.765, green: 0.824, blue: 0.722, alpha: 0.32)
)
blob(
    center: CGPoint(x: 110, y: 50),
    radius: 210,
    color: NSColor(srgbRed: 0.851, green: 0.816, blue: 0.698, alpha: 0.28)
)

func slot(centerX: CGFloat) {
    let slotRect = NSRect(x: centerX - 72, y: height / 2 - 72, width: 144, height: 144)
    let path = NSBezierPath(roundedRect: slotRect, xRadius: 24, yRadius: 24)
    NSColor.white.withAlphaComponent(0.38).setFill()
    path.fill()
    NSColor.white.withAlphaComponent(0.62).setStroke()
    path.lineWidth = 1
    path.stroke()
}

slot(centerX: 160)
slot(centerX: 500)

let ink = NSColor(srgbRed: 0.122, green: 0.118, blue: 0.114, alpha: 1)
let ink2 = NSColor(srgbRed: 0.365, green: 0.345, blue: 0.310, alpha: 1)
let ink3 = NSColor(srgbRed: 0.553, green: 0.522, blue: 0.471, alpha: 1)
let accent = NSColor(srgbRed: 0.722, green: 0.361, blue: 0.220, alpha: 0.9)

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    string.draw(in: NSRect(x: 30, y: y, width: width - 60, height: font.pointSize * 1.8))
}

drawCentered("FreeAPI", y: 350, font: .systemFont(ofSize: 26, weight: .semibold), color: ink)
drawCentered("拖到 Applications 文件夹完成安装", y: 322, font: .systemFont(ofSize: 12), color: ink2)
drawCentered("FreeAPI 2.0 · macOS 15+", y: 26, font: .systemFont(ofSize: 9, weight: .medium), color: ink3)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 250, y: height / 2))
arrow.curve(
    to: NSPoint(x: 402, y: height / 2),
    controlPoint1: NSPoint(x: 300, y: height / 2 + 28),
    controlPoint2: NSPoint(x: 352, y: height / 2 + 28)
)
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
accent.setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 390, y: height / 2 + 11))
arrowHead.line(to: NSPoint(x: 404, y: height / 2))
arrowHead.line(to: NSPoint(x: 390, y: height / 2 - 11))
arrowHead.lineWidth = 2.5
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
accent.setStroke()
arrowHead.stroke()

drawCentered("拖拽", y: height / 2 + 32, font: .systemFont(ofSize: 10, weight: .medium), color: accent)

NSGraphicsContext.restoreGraphicsState()

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources/dmg-background.png")
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("无法生成背景图")
}
try! png.write(to: output)
print("wrote \(output.path)")
