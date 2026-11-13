// Fallback frame extractor for scripts/extract-frame.sh when ffmpeg is missing.
// Usage: swift extract-frame.swift <clip> <second> <out.png>
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4, let second = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: extract-frame.swift <clip> <second> <out.png>\n".utf8))
    exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

let semaphore = DispatchSemaphore(value: 0)
var status: Int32 = 0
generator.generateCGImageAsynchronously(for: CMTime(seconds: second, preferredTimescale: 600)) { image, _, error in
    defer { semaphore.signal() }
    guard let image,
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        FileHandle.standardError.write(Data("failed: \(String(describing: error))\n".utf8))
        status = 1
        return
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { status = 1 }
}
semaphore.wait()
exit(status)
