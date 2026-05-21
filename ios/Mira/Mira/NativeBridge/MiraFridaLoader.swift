import Foundation

enum MiraFridaLoader {
    static func ensureLoaded() {
        MiraDiagnostics.log(level: "INFO", scope: "frida", message: "ensure load requested")
        _ = mira_ios_frida_loader_ensure_loaded()
        MiraDiagnostics.log(level: isLoaded ? "INFO" : "ERROR", scope: "frida", message: "ensure load completed", details: ["status": statusText])
    }

    static var statusText: String {
        String(cString: mira_ios_frida_loader_status())
    }

    static var isLoaded: Bool {
        mira_ios_frida_loader_is_loaded() != 0
    }
}
