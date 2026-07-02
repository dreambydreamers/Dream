import Foundation
import Combine

/// Persists the set of saved feed-card IDs locally (UserDefaults).
/// Keyed by Dream.feedID (UUID) so each video card is saved individually.
@MainActor
final class SavedDreamsStore: ObservableObject {
    static let shared = SavedDreamsStore()

    @Published private(set) var savedIDs: Set<UUID> = []
    private let key = "dream_saved_feed_ids"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let strings = try? JSONDecoder().decode([String].self, from: data) {
            savedIDs = Set(strings.compactMap(UUID.init(uuidString:)))
        }
    }

    func toggle(_ feedID: UUID) {
        if savedIDs.contains(feedID) {
            savedIDs.remove(feedID)
        } else {
            savedIDs.insert(feedID)
        }
        persist()
    }

    func isSaved(_ feedID: UUID) -> Bool {
        savedIDs.contains(feedID)
    }

    private func persist() {
        let data = try? JSONEncoder().encode(savedIDs.map(\.uuidString))
        UserDefaults.standard.set(data, forKey: key)
    }
}
