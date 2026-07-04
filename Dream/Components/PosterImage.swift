import Foundation
import Combine
import SwiftUI
import UIKit

/// Cached poster image used by feed/profile/chat video thumbnails.
struct PosterImage: View {
    let url: URL?
    let category: DreamCategory

    @StateObject private var loader = PosterImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ScenePoster(category: category)
            }
        }
        .task(id: url) {
            await loader.load(url)
        }
    }
}

@MainActor
private final class PosterImageLoader: ObservableObject {
    @Published var image: UIImage?

    private static let cache = NSCache<NSURL, UIImage>()
    private var loadedURL: URL?

    func load(_ url: URL?) async {
        guard loadedURL != url else { return }
        loadedURL = url

        guard let url else {
            image = nil
            return
        }

        let key = url as NSURL
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }

        image = nil
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let decoded = UIImage(data: data) else { return }
            Self.cache.setObject(decoded, forKey: key)
            if loadedURL == url {
                image = decoded
            }
        } catch {
            if loadedURL == url {
                image = nil
            }
        }
    }
}
