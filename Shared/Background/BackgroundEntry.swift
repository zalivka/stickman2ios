import CoreGraphics
import Foundation

/// One pickable background. Android `BackgroundEntry`; the id is the legacy
/// `scene:name` form, e.g. `zalivka.farm:barn` for a pack, `jungle:beach` for an asset,
/// `usermade:1790000000000` for a drawn one in `bgs`.
struct BackgroundEntry: Identifiable {
    enum Source {
        case pack(packName: String, ownName: String)
        case embedded(sceneName: String, ownName: String)
        case user(ownName: String)
    }

    static let userFolder = "user"

    var source: Source
    var thumb: CGImage?

    var id: String {
        switch source {
        case .pack(let packName, let ownName):
            return "\(packName):\(ownName)"
        case .embedded(let sceneName, let ownName):
            return "\(sceneName):\(ownName)"
        case .user(let ownName):
            return BackgroundStore.usermadePrefix + ownName
        }
    }

    var folder: String {
        switch source {
        case .pack(let packName, _):
            return packName
        case .embedded(let sceneName, _):
            return sceneName
        case .user:
            return Self.userFolder
        }
    }
}
