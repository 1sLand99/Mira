import SwiftUI

@main
struct MiraApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = MiraControlViewModel()

    init() {
        NSHomeDirectory().withCString { homePointer in
            _ = mira_ios_frida_service_start(homePointer)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onChange(of: scenePhase) { nextPhase in
                    viewModel.handleScenePhase(nextPhase)
                }
        }
    }
}
