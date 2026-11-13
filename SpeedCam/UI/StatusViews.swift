import SwiftUI

/// Full-screen designed state for the camera area: icon, one line, one action (AC-003, AC-113).
struct CameraStateView: View {
    let state: DesignedState
    let identifier: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: state.icon)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)
            Text(state.message)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .frame(maxWidth: 420)
            Button(state.actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .accessibilityIdentifier("state.action")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// Non-blocking banner with one action (AC-005, AC-075).
struct BannerView: View {
    let state: DesignedState
    let identifier: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.icon)
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(state.message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(state.actionTitle, action: action)
                .font(.footnote.weight(.bold))
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityIdentifier("\(identifier).action")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// Error/notice card: specific cause + exactly one action (R-15, AC-078).
struct NoticeView: View {
    let kind: NoticeKind
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(kind.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(kind.actionTitle, action: action)
                .font(.subheadline.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(kind.action == .ok ? .gray : .red)
                .accessibilityIdentifier("notice.action")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notice")
    }
}

/// Pulsing red dot + elapsed timer (AC-020).
struct RecordingIndicator: View {
    let viewModel: CameraViewModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .opacity(pulse ? 0.25 : 1)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
                .accessibilityHidden(true)
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(verbatim: viewModel.elapsedText(at: context.date))
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityLabel(viewModel.elapsedText(at: context.date))
                    .accessibilityIdentifier("recording.timer")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.recording)
        .accessibilityIdentifier("recording.indicator")
    }
}

struct SavingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white)
            Text(L10n.saving).font(.headline).foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("saving.indicator")
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        Text(L10n.savedToPhotos)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.green.opacity(0.85), in: Capsule())
            .accessibilityIdentifier("toast")
    }
}

/// "No audio — Mic off" badge; tapping explains and offers Open Settings (AC-004).
struct MicOffBadge: View {
    let viewModel: CameraViewModel
    @State private var showDialog = false

    var body: some View {
        Button {
            showDialog = true
        } label: {
            Label(L10n.micOffBadge, systemImage: DesignedState.micOff.icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.micOffBadge)
        .accessibilityIdentifier("badge.mic")
        .confirmationDialog(DesignedState.micOff.message, isPresented: $showDialog, titleVisibility: .visible) {
            Button(DesignedState.micOff.actionTitle) { viewModel.openSystemSettings() }
        }
    }
}
