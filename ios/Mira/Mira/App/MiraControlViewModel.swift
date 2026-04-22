import Foundation

final class MiraControlViewModel: ObservableObject {
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

    init() {
        relayURL = UserDefaults.standard.string(forKey: DefaultsKey.relayURL) ?? ""
        refreshNativeStatus()
    }

    deinit {
        statusTimer?.invalidate()
    }

    func connectRelay() {
        let normalized = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            statusText = "relay url required"
            return
        }
        relayURL = normalized
        if MiraNativeStatus.startRelay(url: normalized) {
            statusText = MiraNativeStatus.current.ptyLifecycle
            startStatusPolling()
        } else {
            statusText = MiraNativeStatus.current.ptyLifecycle
        }
    }

    func disconnectRelay() {
        statusTimer?.invalidate()
        statusTimer = nil
        MiraNativeStatus.stopRelay()
        refreshNativeStatus()
    }

    private func startStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshNativeStatus()
        }
        RunLoop.main.add(statusTimer!, forMode: .common)
    }

    private func refreshNativeStatus() {
        let native = MiraNativeStatus.current
        statusText = "\(native.backendName): \(native.ptyLifecycle)"
    }
}
