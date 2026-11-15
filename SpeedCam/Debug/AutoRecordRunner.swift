#if DEBUG
import Foundation

/// Drives the simulator-only end-to-end recording hook (AC-093). Compiled out of Release (AC-103).
@MainActor
struct AutoRecordRunner {
    let viewModel: CameraViewModel
    let seconds: Int

    func run() async {
        guard seconds > 0 else { return }
        while viewModel.previewImage == nil && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled, viewModel.canRecord else { return }
        await viewModel.tapRecordAsync()
        guard viewModel.coordinator.isRecording else { return }
        try? await Task.sleep(for: .seconds(seconds))
        if viewModel.coordinator.isRecording {
            await viewModel.coordinator.stop(.user)
        }
    }
}
#endif
