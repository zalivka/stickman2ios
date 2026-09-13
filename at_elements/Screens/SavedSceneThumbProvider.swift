import Foundation
import Kingfisher

struct SavedSceneThumbProvider: ImageDataProvider {
    let url: URL
    let cacheKey: String

    init(item: SavedScenes.Item) {
        url = item.url
        cacheKey = item.cacheKey
    }

    func data(handler: @escaping @Sendable (Result<Data, any Error>) -> Void) {
        let url = url
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let zip = try Data(contentsOf: url)
                let names = ZipStore.names(in: zip)
                let thumbName: String
                if names.contains("thumb_big.png") {
                    thumbName = "thumb_big.png"
                } else if names.contains("thumb.png") {
                    thumbName = "thumb.png"
                } else {
                    fatalError("SavedSceneThumbProvider '\(url.lastPathComponent)' has no thumb_big.png or thumb.png")
                }
                handler(.success(ZipStore.data(named: thumbName, in: zip)))
            } catch {
                handler(.failure(error))
            }
        }
    }
}
