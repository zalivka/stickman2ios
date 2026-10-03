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
                let names = try ZipStore.namesThrowing(in: zip)
                let thumbName: String
                if names.contains("thumb_big.png") {
                    thumbName = "thumb_big.png"
                } else if names.contains("thumb.png") {
                    thumbName = "thumb.png"
                } else {
                    throw ZipError(message: "SavedSceneThumbProvider '\(url.lastPathComponent)' has no thumb")
                }
                handler(.success(try ZipStore.dataThrowing(named: thumbName, in: zip)))
            } catch {
                handler(.failure(error))
            }
        }
    }
}
