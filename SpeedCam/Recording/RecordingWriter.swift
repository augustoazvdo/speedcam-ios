import AVFoundation
import CoreVideo
import Foundation

enum RecordingWriterError: Error {
    case cannotStart
}

/// AVAssetWriter (.mov) fed with composited frames in real time. Appends never block; when an
/// input is not ready the sample is dropped (R-10). `finish()` is safe on any stop path (R-09).
final class RecordingWriter: @unchecked Sendable {
    let url: URL
    let movieFragmentInterval: CMTime
    let codec: AVVideoCodecType

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let lock = NSLock()
    private var sessionStart: CMTime?
    private var finished = false
    private var written = 0
    private var dropped = 0

    init(url: URL, videoSize: CGSize, transform: CGAffineTransform, audioSettings: [String: any Sendable]?,
         fragmentInterval: CMTime = CMTime(seconds: 2, preferredTimescale: 600)) throws {
        self.url = url
        movieFragmentInterval = fragmentInterval
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = fragmentInterval
        writer.shouldOptimizeForNetworkUse = false

        codec = Self.preferredCodec(for: writer, size: videoSize)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(codec: codec, size: videoSize))
        video.expectsMediaDataInRealTime = true
        video.transform = transform
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(videoSize.width),
            kCVPixelBufferHeightKey as String: Int(videoSize.height),
        ])
        guard writer.canAdd(video) else { throw RecordingWriterError.cannotStart }
        writer.add(video)
        videoInput = video

        if let audioSettings {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) {
                writer.add(audio)
                audioInput = audio
            } else {
                audioInput = nil
            }
        } else {
            audioInput = nil
        }
        guard writer.startWriting() else { throw RecordingWriterError.cannotStart }
    }

    var isReadyForVideo: Bool { videoInput.isReadyForMoreMediaData }
    var isReadyForAudio: Bool { audioInput?.isReadyForMoreMediaData ?? false }
    var framesWritten: Int { lock.withLock { written } }
    var framesDropped: Int { lock.withLock { dropped } }

    @discardableResult
    func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, writer.status == .writing else { return false }
        if sessionStart == nil {
            writer.startSession(atSourceTime: time)
            sessionStart = time
        }
        guard videoInput.isReadyForMoreMediaData else {
            dropped += 1
            return false
        }
        let ok = adaptor.append(pixelBuffer, withPresentationTime: time)
        if ok { written += 1 } else { dropped += 1 }
        return ok
    }

    @discardableResult
    func appendAudio(_ sample: CMSampleBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, writer.status == .writing, let audioInput, let sessionStart,
              CMSampleBufferGetPresentationTimeStamp(sample) >= sessionStart,
              audioInput.isReadyForMoreMediaData else { return false }
        return audioInput.append(sample)
    }

    func finish() async -> RecordingResult {
        let hasFrames: Bool = lock.withLock {
            guard !finished else { return written > 0 }
            finished = true
            guard written > 0 else {
                writer.cancelWriting()
                return false
            }
            videoInput.markAsFinished()
            audioInput?.markAsFinished()
            return true
        }
        guard hasFrames else {
            try? FileManager.default.removeItem(at: url)
            return .empty
        }
        await writer.finishWriting()
        return writer.status == .completed ? .finished(url) : .failed
    }

    // MARK: Settings

    private static func preferredCodec(for writer: AVAssetWriter, size: CGSize) -> AVVideoCodecType {
        #if targetEnvironment(simulator)
        // The Simulator has no hardware HEVC encoder.
        return .h264
        #else
        let hevc = videoSettings(codec: .hevc, size: size)
        return writer.canApply(outputSettings: hevc, forMediaType: .video) ? .hevc : .h264
        #endif
    }

    private static func videoSettings(codec: AVVideoCodecType, size: CGSize) -> [String: Any] {
        [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: codec == .hevc ? 10_000_000 : 14_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
            ] as [String: Any],
        ]
    }

    static let aacSettings: [String: any Sendable] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 96_000,
    ]
}
