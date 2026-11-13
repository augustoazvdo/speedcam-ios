import CoreImage
import CoreVideo
import Foundation
import Vision
import XCTest
@testable import SpeedCam

/// Top-left-origin RGBA8 bitmap for pixel assertions.
struct Bitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = data
    }

    func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
        let i = (y * width + x) * 4
        return (Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255)
    }

    /// WCAG relative luminance (linear sRGB).
    func luminance(_ x: Int, _ y: Int) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = rgb(x, y)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Fraction of pixels in `rect` that differ from `background` by more than `tolerance` per channel.
    func nonBackgroundFraction(in rect: CGRect, background: (Double, Double, Double), tolerance: Double = 0.04) -> Double {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard r.width > 0, r.height > 0 else { return 0 }
        var count = 0, total = 0
        for y in stride(from: Int(r.minY), to: Int(r.maxY), by: 2) {
            for x in stride(from: Int(r.minX), to: Int(r.maxX), by: 2) {
                let p = rgb(x, y)
                total += 1
                if abs(p.0 - background.0) > tolerance || abs(p.1 - background.1) > tolerance || abs(p.2 - background.2) > tolerance {
                    count += 1
                }
            }
        }
        return Double(count) / Double(total)
    }

    func luminances(in rect: CGRect) -> [Double] {
        let r = rect.integral
        var values: [Double] = []
        for y in stride(from: Int(r.minY), to: Int(r.maxY), by: 2) {
            for x in stride(from: Int(r.minX), to: Int(r.maxX), by: 2) { values.append(luminance(x, y)) }
        }
        return values.sorted()
    }
}

enum TestImages {
    static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    static func solidBuffer(width: Int = 1920, height: Int = 1080, gray: UInt8 = 64) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                    kCVPixelBufferMetalCompatibilityKey as String: true]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        let pb = buffer!
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!
        memset(base, Int32(gray), CVPixelBufferGetBytesPerRow(pb) * height)
        // alpha = 255
        let row = CVPixelBufferGetBytesPerRow(pb)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height { for x in 0..<width { ptr[y * row + x * 4 + 3] = 255 } }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    static func cgImage(_ image: CIImage) -> CGImage {
        context.createCGImage(image, from: image.extent)!
    }

    /// Applies the same transform the movie track carries, giving the frame as a viewer sees it.
    static func upright(_ buffer: CVPixelBuffer, orientation: CaptureOrientation) -> Bitmap {
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: orientation.ciTransform(bufferSize: size))
        return Bitmap(cgImage: cgImage(image))
    }

    static func recognizedText(_ cgImage: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}

extension CGImage {
    func cropped(toTopLeftRect rect: CGRect) -> CGImage { cropping(to: rect.integral)! }
}
