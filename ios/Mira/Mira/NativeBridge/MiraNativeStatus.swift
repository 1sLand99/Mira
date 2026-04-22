import Foundation
import UIKit

struct MiraNativeStatus {
    let backendName: String
    let ptyLifecycle: String

    static var current: MiraNativeStatus {
        let backend = String(cString: mira_pty_ios_backend_name())
        let relay = String(cString: mira_ios_relay_status())
        return MiraNativeStatus(backendName: backend, ptyLifecycle: relay)
    }

    @discardableResult
    static func startRelay(url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let deviceName = UIDevice.current.name
        let home = NSHomeDirectory()
        return trimmed.withCString { relayCString in
            deviceName.withCString { deviceCString in
                home.withCString { homeCString in
                    mira_ios_relay_start(relayCString, deviceCString, homeCString) == 0
                }
            }
        }
    }

    static func stopRelay() {
        mira_ios_relay_stop()
    }
}
