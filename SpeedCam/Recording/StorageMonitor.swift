import Foundation

/// Free space for "important" usage (what iOS reports before purging caches).
struct StorageMonitor: StorageMonitoring {
    let volume: URL

    init(volume: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        self.volume = volume
    }

    func freeBytes() -> Int64 {
        let values = try? volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }
}

#if DEBUG
struct FixedStorage: StorageMonitoring {
    let bytes: Int64
    func freeBytes() -> Int64 { bytes }
}
#endif
