// 產生 App 圖示（橘粉漸層底 + 白色貓掌），由 app/build-app.sh 編譯執行。
// 用法：make-icon <輸出.iconset>，之後以 iconutil -c icns 轉成 AppIcon.icns。
import CoreGraphics
import Foundation
import ImageIO

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

/// 以 1024×1024 座標繪製（原點在左下）。
func drawIcon(_ ctx: CGContext) {
    // 底板：macOS 圖示格線 824×824、圓角約 185
    let plate = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                       cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.28))
    ctx.addPath(plate)
    ctx.setFillColor(rgb(0.97, 0.45, 0.42))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let base = CGGradient(colorsSpace: sRGB,
                          colors: [rgb(1.0, 0.74, 0.40), rgb(0.99, 0.52, 0.36), rgb(0.93, 0.32, 0.50)] as CFArray,
                          locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 260, y: 924), end: CGPoint(x: 760, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let glow = CGGradient(colorsSpace: sRGB, colors: [rgb(1, 1, 1, 0.38), rgb(1, 1, 1, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 320, y: 820), startRadius: 0,
                           endCenter: CGPoint(x: 320, y: 820), endRadius: 560, options: [])
    ctx.restoreGState()

    // 貓掌：一個掌墊 + 四個趾墊，一次填色讓陰影合成一體
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 22, color: rgb(0.55, 0.12, 0.22, 0.35))
    ctx.setFillColor(rgb(1, 1, 1, 0.97))
    let pads: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (512, 400, 360, 300, 0),     // 掌墊
        (318, 590, 128, 168, 24),    // 左趾
        (440, 690, 132, 178, 8),
        (584, 690, 132, 178, -8),
        (706, 590, 128, 168, -24),   // 右趾
    ]
    for (cx, cy, w, h, deg) in pads {
        var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: deg * .pi / 180)
        ctx.addPath(CGPath(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: &t))
    }
    ctx.fillPath()
    ctx.restoreGState()
}

let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in sizes {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    drawIcon(ctx)
    let url = output.appendingPathComponent("icon_\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("無法寫入 \(url.path)")
    }
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("無法寫入 \(url.path)") }
}
