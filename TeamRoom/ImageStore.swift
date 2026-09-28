import Foundation
import Observation
import UIKit

/// Bounded, deduplicated loader for private `/api/media` images (cookie-authenticated).
@MainActor
@Observable
final class ImageStore {
    private let client: TeamRoomClient
    private var cache: [String: UIImage] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(client: TeamRoomClient) {
        self.client = client
    }

    func load(agentId: String, id: String) async -> UIImage? {
        let cacheKey = key(agentId, id)
        if let image = cache[cacheKey] { return image }
        if let task = inFlight[cacheKey] { return await task.value }
        let task = Task.detached(priority: .utility) { [client] () -> UIImage? in
            do {
                let data = try await client.media(agentId: agentId, id: id)
                guard let image = UIImage(data: data) else { return nil }
                return await image.byPreparingThumbnail(ofSize: CGSize(width: 1600, height: 1600)) ?? image
            } catch {
                return nil
            }
        }
        inFlight[cacheKey] = task
        let image = await task.value
        inFlight[cacheKey] = nil
        if let image {
            cache[cacheKey] = image
            order.append(cacheKey)
            trim()
        }
        return image
    }

    private func trim() {
        while order.count > 48, let first = order.first {
            order.removeFirst()
            cache[first] = nil
        }
    }

    private func key(_ agentId: String, _ id: String) -> String { agentId + "/" + id }
}
