import SwiftUI

/// Same controls, order, icons and style in every orientation (AC-051, AC-112):
/// thumbnail · (spacer) · record · unit · settings, leading→trailing in portrait and bottom→top in landscape.
struct ControlsView: View {
    let viewModel: CameraViewModel
    let vertical: Bool

    var body: some View {
        let slots: [AnyView] = [
            AnyView(ThumbnailButton(viewModel: viewModel)),
            AnyView(Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)),
            AnyView(RecordButton(viewModel: viewModel)),
            AnyView(UnitButton(viewModel: viewModel)),
            AnyView(SettingsButton(viewModel: viewModel)),
        ]
        Group {
            if vertical {
                VStack(spacing: 0) {
                    ForEach(Array(slots.indices.reversed()), id: \.self) { i in
                        slots[i].frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 96)
                .padding(.vertical, 12)
            } else {
                HStack(spacing: 0) {
                    ForEach(slots.indices, id: \.self) { i in
                        slots[i].frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 96)
                .padding(.horizontal, 8)
            }
        }
        .background(Color.black)
    }
}

struct RecordButton: View {
    let viewModel: CameraViewModel

    private var recording: Bool { viewModel.coordinator.isRecording }

    var body: some View {
        Button {
            viewModel.tapRecord()
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                RoundedRectangle(cornerRadius: recording ? 6 : 31)
                    .fill(.red)
                    .frame(width: recording ? 30 : 62, height: recording ? 30 : 62)
            }
            .animation(.spring(duration: 0.25), value: recording)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canRecord || viewModel.coordinator.isSaving)
        .opacity(viewModel.canRecord ? 1 : 0.35)
        .accessibilityLabel(recording ? L10n.stop : L10n.record)
        .accessibilityIdentifier("record.button")
    }
}

struct UnitButton: View {
    let viewModel: CameraViewModel

    var body: some View {
        Button {
            viewModel.toggleUnit()
        } label: {
            Text(verbatim: viewModel.settings.unit.label)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .frame(minWidth: 52, minHeight: 36)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.settings.unit.label)
        .accessibilityHint(L10n.switchUnit)
        .accessibilityIdentifier("unit.button")
    }
}

struct SettingsButton: View {
    let viewModel: CameraViewModel

    var body: some View {
        Button {
            viewModel.presentSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.settings)
        .accessibilityIdentifier("settings.button")
    }
}

struct ThumbnailButton: View {
    let viewModel: CameraViewModel

    var body: some View {
        if let thumbnail = viewModel.thumbnail {
            Button {
                viewModel.openLastClip()
            } label: {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.8), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.lastClip)
            .accessibilityIdentifier("thumbnail.button")
        } else {
            // Designed empty state (AC-012, AC-113): icon + one line; the next step is the record button.
            VStack(spacing: 4) {
                Image(systemName: DesignedState.empty.icon)
                    .font(.title3)
                    .frame(width: 52, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4])))
                Text(DesignedState.empty.message)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 76)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DesignedState.empty.message)
            .accessibilityIdentifier("thumbnail.empty")
        }
    }
}
