// 產生 dmg 視窗背景（標題、貓掌足跡箭頭、安裝說明），由 app/build-app.sh 編譯執行。
// 用法：make-dmg-background <輸出資料夾>；輸出 background.png（1x）與 background@2x.png，
// 之後以 tiffutil -cathidpicheck 合成 Retina 用的 background.tiff。
// 版面座標（點，原點左上）需與 build-app.sh 的 Finder 視窗大小、圖示位置一致。
import CoreGraphics
import CoreText
import Foundation
import ImageIO

let canvasWidth: CGFloat = 640
let canvasHeight: CGFloat = 400
let appX: CGFloat = 170
let linkX: CGFloat = 470
let iconY: CGFloat = 205  // 圖示中心（與 build-app.sh 相同）

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

/// 以 y 從上往下的座標轉成 CoreGraphics（原點左下）。
func p(_ x: CGFloat, _ yTop: CGFloat) -> CGPoint { CGPoint(x: x, y: canvasHeight - yTop) }

/// 置中繪製一行文字；yTop 是基線位置。
func text(_ ctx: CGContext, _ s: String, size: CGFloat, weight: String, alpha: CGFloat, yTop: CGFloat) {
    let font = CTFontCreateWithName("PingFangTC-\(weight)" as CFString, size, nil)
    let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: rgb(1, 1, 1, alpha)]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: attrs as [NSAttributedString.Key: Any]))
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: rgb(0.25, 0.05, 0.2, 0.35))
    ctx.textPosition = p((canvasWidth - width) / 2, yTop)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// 貓掌（與 App 圖示同形），中心 c、寬度約 size，趾頭朝 deg 方向（0 = 上）。
func paw(_ ctx: CGContext, center c: CGPoint, size: CGFloat, deg: CGFloat) {
    let pads: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0, -112, 360, 300, 0), (-194, 78, 128, 168, 24), (-72, 178, 132, 178, 8),
        (72, 178, 132, 178, -8), (194, 78, 128, 168, -24),
    ]
    let k = size / 520
    for (cx, cy, w, h, d) in pads {
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: -deg * .pi / 180)
            .scaledBy(x: k, y: k).translatedBy(x: cx, y: cy).rotated(by: d * .pi / 180)
        ctx.addPath(CGPath(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: &t))
    }
    ctx.fillPath()
}

func draw(_ ctx: CGContext) {
    // 底色：App 圖示的橘粉色延伸到梅紫；中段亮度讓 Finder 的淺色／深色模式標籤文字都看得清楚
    let bg = CGGradient(
        colorsSpace: sRGB,
        colors: [rgb(0.98, 0.62, 0.42), rgb(0.86, 0.40, 0.48), rgb(0.50, 0.30, 0.60)] as CFArray,
        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(
        bg, start: p(0, 0), end: p(canvasWidth * 0.35, canvasHeight),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let glow = CGGradient(
        colorsSpace: sRGB, colors: [rgb(1, 1, 1, 0.25), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(
        glow, startCenter: p(canvasWidth / 2, iconY), startRadius: 0,
        endCenter: p(canvasWidth / 2, iconY), endRadius: 300, options: [])

    // 淡淡的大貓掌點綴
    ctx.setFillColor(rgb(1, 1, 1, 0.06))
    paw(ctx, center: p(585, 345), size: 150, deg: -20)
    paw(ctx, center: p(45, 40), size: 90, deg: 160)

    // 標題與說明
    text(ctx, "貓貓谷 for Mac", size: 26, weight: "Semibold", alpha: 1, yTop: 58)
    text(ctx, "把 MacMeow 拖到右邊的「應用程式」資料夾，就安裝好了", size: 15, weight: "Medium", alpha: 0.92, yTop: 92)

    // 貓掌足跡箭頭：從 App 走向「應用程式」
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: rgb(0.3, 0.05, 0.2, 0.3))
    let steps = 4
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps - 1)
        let x = appX + 88 + t * (linkX - appX - 176)
        let y = iconY + (i % 2 == 0 ? 11 : -11)
        ctx.setFillColor(rgb(1, 1, 1, 0.45 + 0.5 * t))
        paw(ctx, center: p(x, y), size: 30, deg: 90)
    }
    ctx.restoreGState()

    text(ctx, "安裝完成後，從「應用程式」資料夾開啟 MacMeow", size: 13, weight: "Regular", alpha: 0.85, yTop: 358)
}

for (name, scale) in [("background.png", 1), ("background@2x.png", 2)] {
    let ctx = CGContext(
        data: nil, width: Int(canvasWidth) * scale, height: Int(canvasHeight) * scale, bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    draw(ctx)
    let url = output.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("無法寫入 \(url.path)")
    }
    let dpi = 72 * scale
    CGImageDestinationAddImage(
        dest, ctx.makeImage()!,
        [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("無法寫入 \(url.path)") }
}
