import Foundation
import AppKit
import CoreGraphics
import ImageIO
import CoreText

// 绘制 RAR 助手图标：橙色渐变圆角底 + 白色拉链 + 白色粗体 "RAR"
// 输出 PNG 到指定目录（供 iconutil 打包成 .icns）

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"

func roundedRectPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func renderIcon(pixels: Int) -> CGImage? {
    let s = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil,
                              width: pixels,
                              height: pixels,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // ---- 背景：橙色渐变圆角矩形 ----
    let radius = s * 0.2237
    ctx.saveGState()
    ctx.addPath(roundedRectPath(CGRect(x: 0, y: 0, width: s, height: s), radius))
    ctx.clip()
    let topColor = CGColor(red: 1.00, green: 0.71, blue: 0.33, alpha: 1.0)   // #FFB554
    let bottomColor = CGColor(red: 0.90, green: 0.40, blue: 0.05, alpha: 1.0) // #E6660D
    if let gradient = CGGradient(colorsSpace: colorSpace,
                                 colors: [topColor, bottomColor] as CFArray,
                                 locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: s * 0.5, y: s),
                               end: CGPoint(x: s * 0.5, y: 0),
                               options: [])
    }
    // 顶部柔光
    if let gloss = CGGradient(colorsSpace: colorSpace,
                              colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.28),
                                       CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray,
                              locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gloss,
                               start: CGPoint(x: s * 0.5, y: s),
                               end: CGPoint(x: s * 0.5, y: s * 0.45),
                               options: [])
    }
    ctx.restoreGState()

    // ---- 拉链（上半部）----
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let zipY = s * 0.735
    let zipLeft = s * 0.225
    let zipRight = s * 0.775
    let zipWidth = zipRight - zipLeft

    // 齿：上下各一排小方块
    let toothCount = 8
    let toothWidth = zipWidth / CGFloat(toothCount) * 0.42
    let toothHeight = s * 0.052
    ctx.setFillColor(white)
    for index in 0..<toothCount {
        let step = zipWidth / CGFloat(toothCount)
        let x = zipLeft + step * CGFloat(index) + (step - toothWidth) / 2
        ctx.fill(CGRect(x: x, y: zipY - toothHeight, width: toothWidth, height: toothHeight))
        ctx.fill(CGRect(x: x, y: zipY + s * 0.056, width: toothWidth, height: toothHeight))
    }
    // 链条主体
    ctx.setFillColor(white)
    ctx.addPath(roundedRectPath(CGRect(x: zipLeft, y: zipY - s * 0.012,
                                       width: zipWidth, height: s * 0.068), s * 0.02))
    ctx.fillPath()
    // 拉链头（右侧滑块）
    let sliderSize = s * 0.115
    ctx.addPath(roundedRectPath(CGRect(x: zipRight - sliderSize * 0.55,
                                       y: zipY - sliderSize * 0.42,
                                       width: sliderSize * 0.62,
                                       height: sliderSize * 0.84), s * 0.028))
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(red: 0.90, green: 0.40, blue: 0.05, alpha: 1.0))
    ctx.setLineWidth(s * 0.016)
    ctx.stroke(CGRect(x: zipRight - sliderSize * 0.42, y: zipY + sliderSize * 0.30,
                      width: sliderSize * 0.34, height: sliderSize * 0.62).insetBy(dx: s * 0.008, dy: s * 0.008))

    // ---- 文字 "RAR"（下半部）----
    let fontSize = s * 0.325
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: white
    ]
    let attributed = NSAttributedString(string: "RAR", attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetImageBounds(line, ctx)
    let centerY = s * 0.395
    ctx.textPosition = CGPoint(x: s / 2 - bounds.width / 2 - bounds.minX,
                               y: centerY - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, ctx)

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        print("  无法创建 PNG：\(path)")
        return
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let fileManager = FileManager.default
try? fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// iconutil 要求的命名：icon_16x16.png / icon_16x16@2x.png / ...
let targets: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in targets {
    guard let image = renderIcon(pixels: pixels) else {
        print("  渲染失败：\(name)")
        continue
    }
    writePNG(image, to: outputDir + "/" + name)
    print("  生成 \(name) (\(pixels)px)")
}
print("图标 PNG 输出目录：\(outputDir)")
