import CoreGraphics
import Foundation

/// One pickable background. Android `BackgroundEntry`; the id is the legacy
/// `scene:name` form, e.g. `zalivka.farm:barn` for a pack, `jungle:beach` for an asset.
struct BackgroundEntry: Identifiable {
    enum Source {
        case pack(packName: String, ownName: String)
        case embedded(sceneName: String, ownName: String)
    }

    var source: Source
    var thumb: CGImage?

    var id: String {
        switch source {
        case .pack(let packName, let ownName):
            return "\(packName):\(ownName)"
        case .embedded(let sceneName, let ownName):
            return "\(sceneName):\(ownName)"
        }
    }

    var folder: String {
        switch source {
        case .pack(let packName, _):
            return packName
        case .embedded(let sceneName, _):
            return sceneName
        }
    }
}
