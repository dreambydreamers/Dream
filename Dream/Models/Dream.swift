import Foundation

struct JourneyStep: Identifiable, Hashable {
    let id: UUID
    let stage: String
    let date: String
    let done: Bool
    let note: String

    init(id: UUID = UUID(), stage: String, date: String, done: Bool, note: String) {
        self.id = id
        self.stage = stage
        self.date = date
        self.done = done
        self.note = note
    }
}

enum DreamStage: String {
    case idea = "Just an Idea"
    case early = "Early Progress"
    case needs = "Needs Help"
    case almost = "Almost There"
}

struct Dream: Identifiable, Hashable {
    let id: UUID
    /// Owner's `auth.users` id — used to open the author's profile from the feed.
    let ownerId: UUID
    let name: String
    let handle: String
    let title: String
    let category: DreamCategory
    let stage: DreamStage
    let help: [String]
    let avatarSeed: Int
    let location: String
    let distance: String
    let desc: String
    let journey: [JourneyStep]
    let supporters: Int
    let offers: Int
    let viewsLabel: String
    /// True if the owner picked this as their featured ("main") dream.
    var isFeatured: Bool = false
    /// Optional URL for the primary uploaded video. `nil` for sample data.
    var videoURL: URL? = nil
    /// Optional URL for the video poster image.
    var posterURL: URL? = nil
    /// Storage path of the primary video in the private `dream-videos` bucket.
    /// Used to fetch a signed playback URL on demand. `nil` when there's no video.
    var videoStoragePath: String? = nil
}

extension Dream {
    func matched(against skills: [String]) -> String? {
        help.first(where: { skills.contains($0) })
    }
}
