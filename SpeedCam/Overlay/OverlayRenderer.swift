import CoreGraphics
import CoreImage
import CoreText
import CoreVideo
import Foundation
import Metal
import UIKit

/// Draws the speedometer plate (ASM-003) and composites it onto sensor-orientation frames so it is
/// upright in the viewer's chosen corner after the track transform. The same output feeds the
/// writer and the live preview, so preview == file (AC-011).
final class OverlayRenderer: @unchecked Sendable {
    let context: CIContext
    private let lock = NSLock()
    private var cachedKey: OverlayKey?
    private var cachedImage: CGImage?
    private var cachedCIImage: CIImage?
    private var layouts: [Int: Layout] = [:]
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    init() {
        // No color management: camera/synthetic pixels pass through untouched.
        let options: [CIContextOption: Any] = [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    // MARK: Compositing

    func render(_ input: CVPixelBuffer, model: OverlayModel) -> CVPixelBuffer? {
        let bufferSize = CGSize(width: CVPixelBufferGetWidth(input), height: CVPixelBufferGetHeight(input))
        let upright = model.orientation.uprightSize(for: bufferSize)
        let plate = plateRect(for: model, uprightSize: upright)
        let overlay = overlayCIImage(for: model, uprightSize: upright)
            .transformed(by: CGAffineTransform(translationX: plate.minX, y: upright.height - plate.maxY))
            .transformed(by: model.orientation.ciTransform(bufferSize: bufferSize).inverted())
        let composite = overlay.composited(over: CIImage(cvPixelBuffer: input))
        guard let output = makeOutputBuffer(size: bufferSize) else { return nil }
        context.render(composite, to: output, bounds: CGRect(origin: .zero, size: bufferSize), colorSpace: nil)
        return output
    }

    /// Upright, downscaled image of a composited buffer for the on-screen preview.
    func previewImage(from buffer: CVPixelBuffer, orientation: CaptureOrientation, maxDimension: CGFloat) -> CGImage? {
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        var image = CIImage(cvPixelBuffer: buffer).transformed(by: orientation.ciTransform(bufferSize: size))
        let scale = min(1, maxDimension / max(size.width, size.height))
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return context.createCGImage(image, from: image.extent.integral)
    }

    private func makeOutputBuffer(size: CGSize) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if pool == nil || poolSize != size {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey as String: 6] as CFDictionary, attrs as CFDictionary, &newPool)
            pool = newPool
            poolSize = size
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    // MARK: Layout

    /// Plate rectangle in the upright frame, top-left origin.
    func plateRect(for model: OverlayModel, uprightSize size: CGSize) -> CGRect {
        let layout = layout(shortSide: Int(min(size.width, size.height)))
        let w = layout.plateSize.width, h = layout.plateSize.height, m = layout.margin
        switch model.corner {
        case .topLeft: return CGRect(x: m, y: m, width: w, height: h)
        case .topRight: return CGRect(x: size.width - m - w, y: m, width: w, height: h)
        case .bottomLeft: return CGRect(x: m, y: size.height - m - h, width: w, height: h)
        case .bottomRight: return CGRect(x: size.width - m - w, y: size.height - m - h, width: w, height: h)
        }
    }

    private struct Layout {
        let margin: CGFloat
        let padding: CGFloat
        let plateSize: CGSize
        let speedFont: CTFont
        let unitFont: CTFont
        let smallFont: CTFont
    }

    private func layout(shortSide: Int) -> Layout {
        lock.lock()
        defer { lock.unlock() }
        if let cached = layouts[shortSide] { return cached }
        let s = CGFloat(shortSide)
        let speedFont = Self.font(size: (0.13 * s).rounded(), weight: .heavy, rounded: true)
        let unitFont = Self.font(size: (0.042 * s).rounded(), weight: .semibold, rounded: true)
        let smallFont = Self.font(size: (0.03 * s).rounded(), weight: .medium, rounded: false)
        let padding = (0.03 * s).rounded()
        let barsWidth = Self.barsSize(font: smallFont).width + padding * 0.4
        let gpsWidth = [GPSStatus.good, .weak, .noFix, .off]
            .map { barsWidth + Self.width(OverlayFormat.gpsLabel($0), font: smallFont) }.max() ?? 0
        let contentWidth = max(Self.width("00/00/0000 00:00:00", font: smallFont),
                               Self.width("888", font: speedFont), gpsWidth)
        let height = padding * 2 + Self.lineHeight(speedFont) + Self.lineHeight(unitFont)
            + padding * 0.5 + Self.lineHeight(smallFont) * 2
        let layout = Layout(margin: (0.04 * s).rounded(), padding: padding,
                            plateSize: CGSize(width: (contentWidth + padding * 2).rounded(.up), height: height.rounded(.up)),
                            speedFont: speedFont, unitFont: unitFont, smallFont: smallFont)
        layouts[shortSide] = layout
        return layout
    }

    // MARK: Overlay image

    private struct OverlayKey: Hashable {
        let display: String
        let unit: String
        let gps: GPSStatus
        let timestamp: String
        let shortSide: Int
    }

    private func key(for model: OverlayModel, uprightSize: CGSize) -> OverlayKey {
        OverlayKey(display: model.reading.display(locale: model.locale), unit: model.reading.unit.label,
                   gps: model.reading.gps,
                   timestamp: OverlayFormat.timestamp(model.date, timeZone: model.timeZone, locale: model.locale),
                   shortSide: Int(min(uprightSize.width, uprightSize.height)))
    }

    /// Upright plate image; cached while text/state is unchanged (≤ 1×/s for the clock, R-21).
    func overlayImage(for model: OverlayModel, uprightSize: CGSize) -> CGImage {
        let key = key(for: model, uprightSize: uprightSize)
        lock.lock()
        if key == cachedKey, let cachedImage {
            lock.unlock()
            return cachedImage
        }
        lock.unlock()
        let image = draw(key)
        lock.lock()
        cachedKey = key
        cachedImage = image
        cachedCIImage = CIImage(cgImage: image)
        lock.unlock()
        return image
    }

    private func overlayCIImage(for model: OverlayModel, uprightSize: CGSize) -> CIImage {
        let image = overlayImage(for: model, uprightSize: uprightSize)
        return lock.withLock { cachedImage === image ? cachedCIImage : nil } ?? CIImage(cgImage: image)
    }

    private func draw(_ key: OverlayKey) -> CGImage {
        let layout = layout(shortSide: key.shortSide)
        let size = layout.plateSize
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let p = layout.padding
        let radius = p * 0.9
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.6))
        ctx.fillPath()

        let white = CGColor(gray: 1, alpha: 1)
        var top = p // distance from the plate's top edge
        func drawLine(_ text: String, font: CTFont, color: CGColor, x: CGFloat) {
            let line = CTLineCreateWithAttributedString(Self.attributed(text, font: font, color: color))
            let ascent = CTFontGetAscent(font)
            ctx.textPosition = CGPoint(x: x, y: size.height - top - ascent)
            CTLineDraw(line, ctx)
            top += Self.lineHeight(font)
        }

        drawLine(key.display, font: layout.speedFont, color: white, x: p)
        drawLine(key.unit, font: layout.unitFont, color: white, x: p)
        top += p * 0.5

        // GPS indicator: signal bars + label.
        let small = layout.smallFont
        let bars = Self.barsSize(font: small)
        let barColor: CGColor
        let filled: Int
        switch key.gps {
        case .good: (barColor, filled) = (CGColor(red: 0.2, green: 0.85, blue: 0.35, alpha: 1), 4)
        case .weak: (barColor, filled) = (CGColor(red: 1, green: 0.8, blue: 0.1, alpha: 1), 2)
        case .noFix: (barColor, filled) = (CGColor(red: 1, green: 0.27, blue: 0.23, alpha: 1), 0)
        case .off: (barColor, filled) = (CGColor(gray: 0.6, alpha: 1), 0)
        }
        let lineH = Self.lineHeight(small)
        let barBottom = size.height - top - lineH + CTFontGetDescent(small) + lineH * 0.1
        let barW = bars.width / 7
        for i in 0..<4 {
            let h = bars.height * CGFloat(i + 1) / 4
            let rect = CGRect(x: p + CGFloat(i) * barW * 2, y: barBottom, width: barW, height: h)
            if i < filled {
                ctx.setFillColor(barColor)
                ctx.fill(rect)
            } else {
                ctx.setStrokeColor(barColor)
                ctx.setLineWidth(max(1, barW * 0.25))
                ctx.stroke(rect.insetBy(dx: barW * 0.12, dy: barW * 0.12))
            }
        }
        if key.gps == .off {
            ctx.setStrokeColor(barColor)
            ctx.setLineWidth(max(1, barW * 0.35))
            ctx.move(to: CGPoint(x: p, y: barBottom))
            ctx.addLine(to: CGPoint(x: p + bars.width, y: barBottom + bars.height))
            ctx.strokePath()
        }
        let labelColor = key.gps == .good ? white : barColor
        drawLine(OverlayFormat.gpsLabel(key.gps), font: small, color: labelColor, x: p + bars.width + p * 0.4)
        drawLine(key.timestamp, font: small, color: white, x: p)
        return ctx.makeImage()!
    }

    // MARK: Text helpers

    private static func font(size: CGFloat, weight: UIFont.Weight, rounded: Bool) -> CTFont {
        var descriptor = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight).fontDescriptor
        if rounded, let roundedDescriptor = descriptor.withDesign(.rounded) {
            descriptor = roundedDescriptor
        }
        return UIFont(descriptor: descriptor, size: size) as CTFont
    }

    private static func attributed(_ text: String, font: CTFont, color: CGColor) -> CFAttributedString {
        NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
    }

    private static func width(_ text: String, font: CTFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed(text, font: font, color: CGColor(gray: 1, alpha: 1)))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func lineHeight(_ font: CTFont) -> CGFloat {
        CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    private static func barsSize(font: CTFont) -> CGSize {
        let h = CTFontGetCapHeight(font)
        return CGSize(width: h * 1.4, height: h)
    }
}
