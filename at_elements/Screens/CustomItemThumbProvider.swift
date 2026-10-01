import Foundation
import Kingfisher

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
                let thumb = try ZipStore.dataThrowing(named: "thumb.png", in: zip)
                handler(.success(thumb))
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
