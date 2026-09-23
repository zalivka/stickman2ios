import Foundation
import Kingfisher

struct MissingThumb: Error {
    var file: String
}

struct CustomItemThumbProvider: ImageDataProvider {
    let url: URL
    let cacheKey: String

    init(item: CustomItems.Item) {
        url = item.url
        cacheKey = item.cacheKey
    }

    func data(handler: @escaping @Sendable (Result<Data, any Error>) -> Void) {
        let url = url
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let zip = try Data(contentsOf: url)
                if !ZipStore.contains("thumb.png", in: zip) {
                    handler(.failure(MissingThumb(file: url.lastPathComponent)))
                    return
                }
                handler(.success(ZipStore.data(named: "thumb.png", in: zip)))
            } catch {
                handler(.failure(error))
            }
        }
    }
}
