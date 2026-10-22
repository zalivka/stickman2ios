import Foundation

/// Facts written once and kept. `boot` records the version of the first launch that sees an empty registry.
enum Records {
    private static let firstInstalledVersionKey = "records.firstInstalledVersion"

    /// Marketing version (`CFBundleShortVersionString`) from the first launch that ran `boot`.
    static var firstInstalledVersion: String {
        guard let stored = UserDefaults.standard.string(forKey: firstInstalledVersionKey),
              !stored.isEmpty
        else {
            fatalError("Records missing \(firstInstalledVersionKey); boot() did not run")
        }
        return stored
    }

    static func boot() {
        if let stored = UserDefaults.standard.string(forKey: firstInstalledVersionKey), !stored.isEmpty {
            return
        }
        UserDefaults.standard.set(currentVersion(), forKey: firstInstalledVersionKey)
    }

    private static func currentVersion() -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !value.isEmpty
        else {
            // Info.plist: a failure here ships broken, fires on first debug run
            fatalError("Records missing CFBundleShortVersionString")
        }
        return value
    }
}
