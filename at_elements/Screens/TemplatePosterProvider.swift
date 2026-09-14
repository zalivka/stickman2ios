import Foundation
import Kingfisher

struct TemplatePosterProvider: ImageDataProvider {
    let fullName: String
    let cacheKey: String

    init(item: Item) {
        fullName = item.makeFullName()
        cacheKey = "\(AssetTemplates.packName):\(item.systemName)"
    }

    func data(handler: @escaping @Sendable (Result<Data, any Error>) -> Void) {
        let fullName = fullName
        DispatchQueue.global(qos: .userInitiated).async {
            handler(.success(AssetTemplates.poster(fullname: fullName)))
        }
    }
}
