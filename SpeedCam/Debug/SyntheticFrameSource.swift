#if DEBUG
import AVFoundation
import CoreGraphics
import CoreText
import CoreVideo
import Foundation
import UIKit

/// Draws 1920×1080 BGRA test frames (moving gradient, frame counter, clock). Content is drawn
/// rotated like a real sensor would see an upright scene, so it is upright after the track transform.
final class SyntheticFrameGenerator: @unchecked Sendable {
    let size: CGSize
    private var pool: CVPixelBufferPool?
    private let font = UIFont.monospacedDigitSystemFont(ofSize: 64, weight: .bold) as CTFont
    private let smallFont = UIFont.monospacedDigitSystemFont(ofSize: 40, weight: .semibold) as CTFont
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(size: CGSize = CGSize(width: 1920, height: 1080)) {
        self.size = size
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
    }

    func frame(index: Int, date: Date, orientation: CaptureOrientation) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let buffer = out else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        let upright = orientation.uprightSize(for: size)
        ctx.concatenate(orientation.ciTransform(bufferSize: size).inverted())

        // Sky-to-road gradient whose hue drifts over time, plus moving lane stripes.
        let phase = CGFloat(index % 300) / 300
        let top = UIColor(hue: 0.58 + 0.1 * phase, saturation: 0.55, brightness: 0.85, alpha: 1).cgColor
        let bottom = UIColor(hue: 0.08, saturation: 0.25, brightness: 0.25, alpha: 1).cgColor
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottom, top] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: upright.height), options: [])
        ctx.setFillColor(UIColor(white: 0.95, alpha: 0.8).cgColor)
        let stripeSpacing = upright.width / 6
        let offset = CGFloat(index * 12).truncatingRemainder(dividingBy: stripeSpacing)
        for i in -1...7 {
            ctx.fill(CGRect(x: CGFloat(i) * stripeSpacing + offset, y: upright.height * 0.18, width: stripeSpacing * 0.45, height: upright.height * 0.02))
        }

        draw("SYNTHETIC CAMERA", font: smallFont, in: ctx, center: CGPoint(x: upright.width / 2, y: upright.height * 0.62))
        draw("frame \(index)", font: font, in: ctx, center: CGPoint(x: upright.width / 2, y: upright.height * 0.52))
        draw(formatter.string(from: date), font: font, in: ctx, center: CGPoint(x: upright.width / 2, y: upright.height * 0.42))
        return buffer
    }

    private func draw(_ text: String, font: CTFont, in ctx: CGContext, center: CGPoint) {
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.9),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: center.x - width / 2, y: center.y)
        CTLineDraw(line, ctx)
    }
}

/// Synthetic camera for the Simulator (AC-090): 30 fps frames with host-clock timestamps.
final class SyntheticFrameSource: FrameSource, @unchecked Sendable {
    let dimensions = CGSize(width: 1920, height: 1080)
    var isAvailable: Bool { true }

    private let queue = DispatchQueue(label: "com.augusto.speedcam.synthetic", qos: .userInteractive)
    private let generator: SyntheticFrameGenerator
    private let orientation: @Sendable () -> CaptureOrientation
    private var timer: DispatchSourceTimer?
    private var index = 0

    init(orientation: @escaping @Sendable () -> CaptureOrientation) {
        self.orientation = orientation
        generator = SyntheticFrameGenerator(size: dimensions)
    }

    func start(onFrame: @escaping @Sendable (VideoFrame) -> Void) {
        queue.async { [self] in
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 30), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let time = CMClockGetTime(CMClockGetHostTimeClock())
                if let buffer = generator.frame(index: index, date: Date(), orientation: orientation()) {
                    onFrame(VideoFrame(pixelBuffer: buffer, time: time))
                }
                index += 1
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }
}

/// Silence for the synthetic pipeline, so exported clips carry an AAC track like real ones.
final class SilentAudioSource: AudioSampleSource, @unchecked Sendable {
    static let sampleRate = 44_100
    static let framesPerBuffer = 1024
    static let writerSettings = RecordingWriter.aacSettings

    var writerSettings: [String: any Sendable] { Self.writerSettings }
    private let queue = DispatchQueue(label: "com.augusto.speedcam.silence", qos: .userInitiated)
    private var timer: DispatchSourceTimer?

    func start(onAudio: @escaping @Sendable (AudioSample) -> Void) {
        queue.async { [self] in
            guard timer == nil else { return }
            var next = CMClockGetTime(CMClockGetHostTimeClock())
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let period = Double(Self.framesPerBuffer) / Double(Self.sampleRate)
            timer.schedule(deadline: .now(), repeating: period, leeway: .milliseconds(2))
            timer.setEventHandler {
                let now = CMClockGetTime(CMClockGetHostTimeClock())
                while next <= now {
                    if let sample = Self.silence(at: next, frames: Self.framesPerBuffer) {
                        onAudio(AudioSample(sampleBuffer: sample))
                    }
                    next = next + CMTime(value: CMTimeValue(Self.framesPerBuffer), timescale: CMTimeScale(Self.sampleRate))
                }
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    static func silence(at time: CMTime, frames: Int) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                               mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let bytes = frames * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let format, let block else { return nil }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format,
                                                            sampleCount: frames, presentationTimeStamp: time,
                                                            packetDescriptions: nil, sampleBufferOut: &sample)
        return sample
    }
}
#endif
