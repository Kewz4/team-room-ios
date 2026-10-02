import Foundation
import ImageIO
import UIKit

/// Loader for private `/api/media` images (cookie-authenticated).
///
/// Memory-bounded: decoded images live in an NSCache with a total cost limit (iOS also purges it under memory
/// pressure), and images are downsampled with ImageIO while decoding, so a 4K screenshot never becomes a 64 MB
/// bitmap. The old cache kept up to 48 images at 1600 px, enough to get the app killed on image-heavy rooms.
@MainActor
final class ImageStore {
    private let client: TeamRoomClient
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(client: TeamRoomClient) {
        self.client = client
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 120
    }

    /// `maxPixel` 700 suits inline thumbnails; the full-screen viewer asks for 2400.
    func load(agentId: String, id: String, maxPixel: CGFloat = 700) async -> UIImage? {
        let key = "\(agentId)/\(id)/\(Int(maxPixel))"
        if let image = cache.object(forKey: key as NSString) { return image }
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached(priority: .utility) { [client] () -> UIImage? in
            guard let data = try? await client.media(agentId: agentId, id: id) else { return nil }
            return ImageStore.downsample(data, maxPixel: maxPixel)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: key as NSString, cost: cost)
        }
        return image
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return UIImage(data: data) }
        return UIImage(cgImage: cgImage)
    }
}
