import Foundation
import Combine
import Supabase

// MARK: - DTOs

struct SearchDreamResult: Codable, Identifiable {
    let id: UUID
    let title: String
    let description: String?
    let category: String
    let ownerId: UUID?
    let ownerName: String?
    let ownerHandle: String?
    let avatarSeed: Int
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, category
        case ownerId    = "owner_id"
        case ownerName  = "owner_name"
        case ownerHandle = "owner_handle"
        case avatarSeed = "avatar_seed"
        case avatarUrl  = "avatar_url"
    }

    var resolvedCategory: DreamCategory { DreamCategory.from(dbValue: category) ?? .tech }
    var avatarURL: URL? { avatarUrl.flatMap(URL.init(string:)) }
}

struct SearchProfileResult: Codable, Identifiable {
    let id: UUID
    let name: String?
    let handle: String?
    let location: String?
    let avatarSeed: Int
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, handle, location
        case avatarSeed = "avatar_seed"
        case avatarUrl  = "avatar_url"
    }

    var avatarURL: URL? { avatarUrl.flatMap(URL.init(string:)) }
}

// MARK: - Repository

@MainActor
final class SearchRepository: ObservableObject {
    static let shared = SearchRepository()

    @Published var dreamResults: [SearchDreamResult] = []
    @Published var profileResults: [SearchProfileResult] = []
    @Published var isSearching = false

    private var searchTask: Task<Void, Never>?

    func search(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count > 1 else {
            dreamResults = []
            profileResults = []
            isSearching = false
            return
        }
        searchTask = Task {
            // 300 ms debounce so we don't fire on every keystroke
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            async let dreams   = fetchDreams(q)
            async let profiles = fetchProfiles(q)
            let (d, p) = await (dreams, profiles)
            guard !Task.isCancelled else { return }
            dreamResults   = d
            profileResults = p
            isSearching    = false
        }
    }

    func clear() {
        searchTask?.cancel()
        dreamResults   = []
        profileResults = []
        isSearching    = false
    }

    // MARK: - Private

    private func fetchDreams(_ q: String) async -> [SearchDreamResult] {
        do {
            return try await SupabaseService.shared.client
                .rpc("search_dreams", params: ["query": q])
                .execute()
                .value
        } catch {
            print("[SearchRepository] dreams error: \(error)")
            return []
        }
    }

    private func fetchProfiles(_ q: String) async -> [SearchProfileResult] {
        do {
            return try await SupabaseService.shared.client
                .rpc("search_profiles", params: ["query": q])
                .execute()
                .value
        } catch {
            print("[SearchRepository] profiles error: \(error)")
            return []
        }
    }
}
