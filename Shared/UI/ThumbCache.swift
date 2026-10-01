import CoreGraphics
import Foundation

/// Decoded chooser thumbs, scene-rail thumbs, and pack logos.
/// A scene drag rebuilds the side panels, so the zip inflate happens once per key.
enum ThumbCache {
    private static let lock = NSLock()
    private static var images: [String: CGImage] = [:]
    /// Bumped when custom-item chooser entries are dropped, so an in-flight decode of those keys is not stored.
    private static var customsGeneration = 0
    private static let observer: NSObjectProtocol = {
        NotificationCenter.default.addObserver(
            forName: .customItemsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            dropChooserCustoms()
        }
    }()

    static func image(_ key: String, make: () -> CGImage) -> CGImage {
        _ = observer
        lock.lock()
        if let cached = images[key] {
            lock.unlock()
            return cached
        }
        let seen = customsGeneration
        lock.unlock()
        let made = make()
        lock.lock()
        let customsStale = key.hasPrefix("chooser:@:") && customsGeneration != seen
        if !customsStale, images[key] == nil {
            images[key] = made
        }
        let stored = images[key] ?? made
        lock.unlock()
        return stored
    }

    private static func dropChooserCustoms() {
        lock.lock()
        images = images.filter { !$0.key.hasPrefix("chooser:@:") }
        customsGeneration += 1
        lock.unlock()
    }
}
