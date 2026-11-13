import AVFoundation
import Foundation

struct RecoveryReport: Equatable, Sendable {
    var recovered: Int
    var unrecoverable: Int

    var notice: NoticeKind? {
        if unrecoverable > 0 { return .unrecoverable }
        if recovered > 0 { return .recovered }
        return nil
    }
}

/// On launch, clips left in `recording/` by a kill/crash are checked: playable ones move to
/// the pending queue (and then to Photos), others are deleted and reported (AC-077).
enum ClipRecovery {
    static func recover(store: ClipStore) async -> RecoveryReport {
        var report = RecoveryReport(recovered: 0, unrecoverable: 0)
        for url in store.inProgressClips() {
            if await isPlayable(url), (try? store.markPending(url)) != nil {
                report.recovered += 1
            } else {
                store.remove(url)
                report.unrecoverable += 1
            }
        }
        return report
    }

    static func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let playable = try? await asset.load(.isPlayable), playable,
              let duration = try? await asset.load(.duration), duration.seconds > 0,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { return false }
        return true
    }
}
