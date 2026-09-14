import Foundation

enum BootLog {
    private static let t0 = ProcessInfo.processInfo.systemUptime

    static func elapsedSeconds() -> String {
        String(format: "%.1f", ProcessInfo.processInfo.systemUptime - t0)
    }

    static func say(_ message: String) {
        let ms = Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
        let thread = Thread.isMainThread ? "main" : "bg"
        print("boot +\(ms)ms uptime=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime)) [\(thread)]: \(message)")
    }
}
