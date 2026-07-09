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
    /// Author's uploaded profile picture, or nil (falls back to the seed avatar).
    var avatarURL: URL? = nil
    let location: String
    let desc: String
    let journey: [JourneyStep]
    let supporters: Int
    let offers: Int
    let viewsLabel: String
    /// True if the owner picked this as their featured ("main") dream.
    var isFeatured: Bool = false
    /// Optional URL for the video poster image.
    var posterURL: URL? = nil
    /// Storage path of the video in the private `dream-videos` bucket.
    /// Used to fetch a signed playback URL on demand. `nil` when there's no video.
    var videoStoragePath: String? = nil
    /// Identity of the specific `dream_videos` row this card represents. A dream
    /// can surface multiple cards in the feed (the main video + update clips),
    /// so video-scoped state (player cache, view identity) keys on this, while
    /// `id`/`ownerId` still point at the parent dream for detail/profile.
    var videoId: UUID? = nil
    /// Per-video heading for "update" clips. `nil` for the cover video, which
    /// shows the dream's own `title`. See `displayTitle`.
    var videoTitle: String? = nil
    /// Per-video caption for update clips. `nil` for older rows and cover
    /// videos, which fall back to the dream's own description.
    var videoCaption: String? = nil
}

extension Dream {
    /// Identity for video-scoped feed concerns (per-video player cache + the
    /// SwiftUI view identity that drives playback). Falls back to the dream id
    /// for dreams without an uploaded video.
    var feedID: UUID { videoId ?? id }

    /// Title to show on this feed card: an update clip's own heading when it has
    /// one, otherwise the parent dream's title.
    var displayTitle: String {
        if let videoTitle, !videoTitle.isEmpty { return videoTitle }
        return title
    }

    /// Description shown on a feed card: an update clip's own caption when it
    /// has one, otherwise the parent dream description.
    var displayDescription: String {
        if let caption = videoCaption?.trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty {
            return caption
        }
        return desc
    }
}
