import SwiftUI

/// Only the unit toggle (US-09) and the overlay corner picker (US-12) (AC-012).
struct SettingsSheet: View {
    let viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.speedUnit) {
                    Picker(L10n.speedUnit, selection: Binding(get: { viewModel.settings.unit },
                                                              set: { viewModel.selectUnit($0) })) {
                        ForEach(SpeedUnit.allCases, id: \.self) { unit in
                            Text(verbatim: unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.unit")
                }
                Section {
                    CornerPicker(viewModel: viewModel)
                } header: {
                    Text(L10n.overlayCorner)
                } footer: {
                    if !viewModel.isCornerPickerEnabled {
                        Text(L10n.appliesNextRecording)
                            .accessibilityIdentifier("settings.cornerHint")
                    }
                }
            }
            .navigationTitle(L10n.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct CornerPicker: View {
    let viewModel: CameraViewModel

    var body: some View {
        let rows: [[OverlayCorner]] = [[.topLeft, .topRight], [.bottomLeft, .bottomRight]]
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { corner in
                        cornerButton(corner)
                    }
                }
            }
        }
        .disabled(!viewModel.isCornerPickerEnabled)
        .opacity(viewModel.isCornerPickerEnabled ? 1 : 0.45)
        .padding(.vertical, 4)
    }

    private func cornerButton(_ corner: OverlayCorner) -> some View {
        let selected = viewModel.selectedCorner == corner
        return Button {
            viewModel.selectCorner(corner)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: alignment(corner)) {
                    RoundedRectangle(cornerRadius: 6).stroke(.secondary, lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: 2).fill(selected ? Color.red : Color.secondary)
                        .frame(width: 22, height: 14)
                        .padding(5)
                }
                .frame(width: 72, height: 44)
                Text(L10n.corner(corner)).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(selected ? Color.red.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.corner(corner))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.corner.\(corner.rawValue)")
    }

    private func alignment(_ corner: OverlayCorner) -> Alignment {
        switch corner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}
