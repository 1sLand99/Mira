import Foundation
import Darwin

@MainActor
enum MiraFridaLoader {
    private static let lock = NSLock()
    private static var attempted = false
    private static var loaded = false
    private static var detail = "idle"

    static func ensureLoaded() {
        lock.lock()
        if attempted {
            lock.unlock()
            return
        }
        attempted = true
        lock.unlock()

        let result = loadFromBundle()

        lock.lock()
        loaded = result.loaded
        detail = result.detail
        lock.unlock()
    }

    static var statusText: String {
        lock.lock()
        defer { lock.unlock() }
        return detail
    }

    static var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loaded
    }

    private static func loadFromBundle() -> (loaded: Bool, detail: String) {
        let candidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("libdynamic.dylib"),
            Bundle.main.bundleURL.appendingPathComponent("libdynamic.dylib"),
        ].compactMap { $0 }

        for candidate in candidates {
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            let handle = candidate.path.withCString { pointer in
                dlopen(pointer, RTLD_NOW)
            }
            if handle != nil {
                return (true, "loaded")
            }
            if let errorPointer = dlerror() {
                return (false, "load failed: \(String(cString: errorPointer))")
            }
            return (false, "load failed: unknown error")
        }

        return (false, "missing bundled gadget")
    }
}
