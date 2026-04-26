import Foundation

enum MiraFridaLoader {
    static func ensureLoaded() {
        _ = mira_ios_frida_loader_ensure_loaded()
    }

    static var statusText: String {
        String(cString: mira_ios_frida_loader_status())
    }

    static var isLoaded: Bool {
        mira_ios_frida_loader_is_loaded() != 0
    }
}
