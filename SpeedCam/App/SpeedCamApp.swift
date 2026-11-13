import SwiftUI

@main
struct SpeedCamApp: App {
    private let environment: AppEnvironment?

    init() {
        #if DEBUG
        environment = LaunchArguments.isHostingUnitTests ? nil : .live()
        #else
        environment = .live()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let environment {
                RootView(environment: environment)
            } else {
                Color.black
            }
        }
    }
}
