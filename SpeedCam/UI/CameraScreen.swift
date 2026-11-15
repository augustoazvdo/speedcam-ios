import SwiftUI
import UIKit

struct CameraScreen: View {
    let viewModel: CameraViewModel

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            // The camera area never sits under the controls, so the burned-in plate stays fully visible (ASM-017).
            ZStack {
                Color.black.ignoresSafeArea()
                if landscape {
                    HStack(spacing: 0) {
                        cameraArea
                        ControlsView(viewModel: viewModel, vertical: true)
                    }
                } else {
                    VStack(spacing: 0) {
                        cameraArea
                        ControlsView(viewModel: viewModel, vertical: false)
                    }
                }
                #if DEBUG
                DebugStateProbe(viewModel: viewModel)
                #endif
            }
            .onAppear { viewModel.orientationChanged(InterfaceOrientation.current(fallbackLandscape: landscape)) }
            .onChange(of: geometry.size) { _, size in
                viewModel.orientationChanged(InterfaceOrientation.current(fallbackLandscape: size.width > size.height))
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: Binding(get: { viewModel.showSettings }, set: { viewModel.showSettings = $0 })) {
            SettingsSheet(viewModel: viewModel)
        }
    }

    private var cameraArea: some View {
        ZStack(alignment: .top) {
            cameraContent
            statusStack
        }
        .overlay(alignment: .bottom) {
            if viewModel.cameraZoomOptions.count > 1 {
                CameraZoomPicker(viewModel: viewModel)
                    .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var cameraContent: some View {
        switch viewModel.cameraState {
        case .ready:
            LivePreview(viewModel: viewModel)
        case .denied:
            CameraStateView(state: .cameraDenied, identifier: "state.cameraDenied") { viewModel.openSystemSettings() }
        case .notDetermined:
            CameraStateView(state: .cameraNotDetermined, identifier: "state.cameraNotDetermined") {
                Task { await viewModel.requestCamera() }
            }
        case .unavailable:
            CameraStateView(state: .cameraUnavailable, identifier: "state.cameraUnavailable") { viewModel.retryCamera() }
        }
    }

    private var statusStack: some View {
        VStack(spacing: 10) {
            if viewModel.coordinator.isRecording {
                RecordingIndicator(viewModel: viewModel)
            } else if viewModel.coordinator.isSaving {
                SavingIndicator()
            }
            if let toast = viewModel.coordinator.toast {
                ToastView(toast: toast)
            }
            if let notice = viewModel.coordinator.notice {
                NoticeView(kind: notice.kind) { viewModel.performNoticeAction() }
            }
            if viewModel.cameraState == .ready {
                if viewModel.showLocationOffBanner {
                    BannerView(state: .locationOff, identifier: "banner.location") { viewModel.openSystemSettings() }
                } else if viewModel.showNoFixBanner {
                    BannerView(state: .noFix, identifier: "banner.noFix") { viewModel.dismissNoFix() }
                }
                if viewModel.showMicOffBadge {
                    MicOffBadge(viewModel: viewModel)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: 560)
        .animation(.easeOut(duration: 0.2), value: viewModel.coordinator.state)
        .animation(.easeOut(duration: 0.2), value: viewModel.coordinator.toast)
    }
}

enum InterfaceOrientation {
    @MainActor
    static func current(fallbackLandscape: Bool) -> CaptureOrientation {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch scene?.interfaceOrientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return fallbackLandscape ? .landscapeRight : .portrait
        }
    }
}

#if DEBUG
/// Exposes state UI tests cannot see otherwise (idle timer, AC-022; locked orientation, AC-052).
struct DebugStateProbe: View {
    let viewModel: CameraViewModel

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("debug.idleTimer")
            .accessibilityValue(viewModel.coordinator.isIdleTimerDisabled ? "disabled" : "enabled")
            .allowsHitTesting(false)
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("debug.orientation")
            .accessibilityValue("live=\(viewModel.orientation.rawValue) locked=\(viewModel.lockedOrientation?.rawValue ?? "none")")
            .allowsHitTesting(false)
    }
}
#endif
