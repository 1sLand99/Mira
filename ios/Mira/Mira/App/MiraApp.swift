import SwiftUI

@main
struct MiraApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = MiraControlViewModel()

    init() {
        MiraDiagnostics.install()
        MiraNativeStatus.installDiagnosticsLogProvider()
        mira_ios_install_log_hooks()
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
