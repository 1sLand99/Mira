import Foundation
import SwiftUI

@MainActor
final class MiraControlViewModel: ObservableObject {
    private enum LaunchEnv {
        static let relayURL = "MIRA_RELAY_URL"
        static let autoConnect = "MIRA_AUTO_CONNECT"
    }

    private enum DefaultsKey {
        static let relayURL = "relay_url"
    }

    @Published var relayURL: String {
        didSet {
            UserDefaults.standard.set(relayURL, forKey: DefaultsKey.relayURL)
        }
    }

    @Published private(set) var statusText: String = "disconnected"
    private var statusTimer: Timer?
    private var relayConnected = false
    private var didRunStartupAutomation = false

    init() {
        let launchRelayURL = ProcessInfo.processInfo.environment[LaunchEnv.relayURL]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        relayURL = launchRelayURL.isEmpty ? (UserDefaults.standard.string(forKey: DefaultsKey.relayURL) ?? "") : launchRelayURL
        refreshNativeStatus()
    }

    func performStartupAutomationIfNeeded() {
        guard !didRunStartupAutomation else { return }
        didRunStartupAutomation = true

        let environment = ProcessInfo.processInfo.environment
        let shouldAutoConnect = (environment[LaunchEnv.autoConnect] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["1", "true", "yes", "on"].contains(shouldAutoConnect) else { return }
        guard !relayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "relay url required"
            return
        }
        connectRelay()
    }

    func connectRelay() {
        let normalized = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            statusText = "relay url required"
            return
        }
        relayURL = normalized
        if MiraNativeStatus.startRelay(url: normalized) {
            relayConnected = true
            MiraRemoteServices.shared.start(relayURL: normalized)
            statusText = MiraNativeStatus.current.ptyLifecycle
            startStatusPolling()
        } else {
            statusText = MiraNativeStatus.current.ptyLifecycle
        }
    }

    func disconnectRelay() {
        statusTimer?.invalidate()
        statusTimer = nil
        relayConnected = false
        MiraRemoteServices.shared.stop()
        MiraNativeStatus.stopRelay()
        refreshNativeStatus()
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            if relayConnected {
                MiraRemoteServices.shared.resumeForSceneActive()
            }
        case .inactive:
            break
        case .background:
            MiraRemoteServices.shared.pauseForSceneStop()
        @unknown default:
            break
        }
    }

    private func startStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNativeStatus()
            }
        }
        RunLoop.main.add(statusTimer!, forMode: .common)
    }

    private func refreshNativeStatus() {
        let native = MiraNativeStatus.current
        statusText = "\(native.backendName): \(native.ptyLifecycle) | frida: \(native.fridaLifecycle)"
    }
}
