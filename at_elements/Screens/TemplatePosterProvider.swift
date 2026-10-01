import Foundation
import Kingfisher

struct TemplatePosterProvider: ImageDataProvider {
    let fullName: String
    let cacheKey: String

    init(item: Item) {
        fullName = item.makeFullName()
        cacheKey = "\(AssetTemplates.packName):\(AssetTemplates.revision()):\(item.systemName)"
    }

    func data(handler: @escaping @Sendable (Result<Data, any Error>) -> Void) {
        let fullName = fullName
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                handler(.success(try AssetTemplates.poster(fullname: fullName)))
            } catch {
                let message = ItemLoadError.text(error)
                DispatchQueue.main.async {
                    ToastCenter.show(message)
                }
                handler(.failure(error))
            }
        }
    }
}
