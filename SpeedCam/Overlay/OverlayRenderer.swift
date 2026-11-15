import CoreGraphics
import CoreImage
import CoreText
import CoreVideo
import Foundation
import Metal
import UIKit

/// Draws the gauge-only overlay (ASM-003, AC-134) and composites it onto sensor-orientation frames so it is
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
        let gaugeRadius: CGFloat
        let gaugeBaselineTop: CGFloat
        let speedFont: CTFont
        let unitFont: CTFont
        let smallFont: CTFont
    }

    private func layout(shortSide: Int) -> Layout {
        lock.lock()
        defer { lock.unlock() }
        if let cached = layouts[shortSide] { return cached }
        let s = CGFloat(shortSide)
        let speedFont = Self.font(size: (0.105 * s).rounded(), weight: .heavy, rounded: true)
        let unitFont = Self.font(size: (0.038 * s).rounded(), weight: .semibold, rounded: true)
        let smallFont = Self.font(size: (0.026 * s).rounded(), weight: .medium, rounded: false)
        let padding = (0.03 * s).rounded()
        let contentWidth = max(Self.width("888", font: speedFont), s * 0.36)
        let width = (contentWidth + padding * 2).rounded(.up)
        let radius = min((width - padding * 2) * 0.48, s * 0.235)
        let baselineTop = radius + padding * 1.55
        let height = baselineTop + Self.lineHeight(smallFont) * 0.45 + padding * 0.75
        let layout = Layout(margin: (0.04 * s).rounded(), padding: padding,
                            plateSize: CGSize(width: width, height: height.rounded(.up)),
                            gaugeRadius: radius, gaugeBaselineTop: baselineTop,
                            speedFont: speedFont, unitFont: unitFont, smallFont: smallFont)
        layouts[shortSide] = layout
        return layout
    }

    // MARK: Overlay image

    private struct OverlayKey: Hashable {
        let display: String
        let unit: String
        let shortSide: Int
    }

    private func key(for model: OverlayModel, uprightSize: CGSize) -> OverlayKey {
        OverlayKey(display: model.reading.display(locale: model.locale), unit: model.reading.unit.label,
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
        let plateRadius = p * 0.9
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil))
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.6))
        ctx.fillPath()

        let white = CGColor(gray: 1, alpha: 1)
        func drawLine(_ text: String, font: CTFont, color: CGColor, x: CGFloat, top: CGFloat) {
            let line = CTLineCreateWithAttributedString(Self.attributed(text, font: font, color: color))
            let ascent = CTFontGetAscent(font)
            ctx.textPosition = CGPoint(x: x, y: size.height - top - ascent)
            CTLineDraw(line, ctx)
        }

        func drawCentered(_ text: String, font: CTFont, top: CGFloat) {
            let textWidth = Self.width(text, font: font)
            drawLine(text, font: font, color: white, x: (size.width - textWidth) / 2, top: top)
        }

        // Gauge track and clipped horizontal gradient, from violet at 0 to blue at the maximum.
        let radius = layout.gaugeRadius
        let center = CGPoint(x: size.width / 2, y: size.height - layout.gaugeBaselineTop)
        let arc = CGMutablePath()
        arc.addArc(center: center, radius: radius, startAngle: .pi, endAngle: 0, clockwise: true)
        ctx.saveGState()
        ctx.addPath(arc)
        ctx.setStrokeColor(CGColor(gray: 0.28, alpha: 1))
        ctx.setLineWidth(radius * 0.13)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.addPath(arc)
        ctx.setLineWidth(radius * 0.115)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let colors = [CGColor(red: 0.78, green: 0.25, blue: 1, alpha: 1), CGColor(red: 0.12, green: 0.32, blue: 1, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: center.x - radius, y: center.y), end: CGPoint(x: center.x + radius, y: center.y), options: [])
        ctx.restoreGState()

        // Thirteen radial divisions form the 0–240 km/h or 0–150 mph scale.
        for index in 0...12 {
            let angle = CGFloat.pi - CGFloat.pi * CGFloat(index) / 12
            let inner = radius * (index.isMultiple(of: 3) ? 0.77 : 0.83)
            let outer = radius * 0.91
            ctx.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            ctx.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.9))
            ctx.setLineWidth(index.isMultiple(of: 3) ? max(2, radius * 0.012) : max(1, radius * 0.007))
            ctx.strokePath()
        }

        drawCentered(key.unit, font: layout.unitFont, top: layout.gaugeBaselineTop - radius * 0.78)
        drawCentered(key.display, font: layout.speedFont, top: layout.gaugeBaselineTop - radius * 0.57)
        let maximum = key.unit == "mph" ? "150" : "240"
        let scaleTop = layout.gaugeBaselineTop - Self.lineHeight(layout.smallFont) * 0.55
        drawLine("0", font: layout.smallFont, color: white, x: center.x - radius - p * 0.1, top: scaleTop)
        drawLine(maximum, font: layout.smallFont, color: white,
                 x: center.x + radius - Self.width(maximum, font: layout.smallFont) + p * 0.1, top: scaleTop)

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

}
