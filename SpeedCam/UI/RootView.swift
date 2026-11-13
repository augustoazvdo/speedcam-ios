import SwiftUI

struct RootView: View {
    let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    private var viewModel: CameraViewModel { environment.viewModel }

    var body: some View {
        Group {
            if viewModel.showOnboarding {
                OnboardingView(viewModel: viewModel)
            } else {
                CameraScreen(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.launch(store: environment.store)
            await viewModel.scenePhaseChanged(.active)
        }
        .onChange(of: scenePhase) { _, phase in
            Task { await viewModel.scenePhaseChanged(phase) }
        }
    }
}
