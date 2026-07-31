import Foundation

/// Build-time feature switches.
enum FeatureFlags {
    /// Routes Discover through the recommendation pipeline
    /// (FeedQueueService + DreamRanking) instead of reverse-chronological.
    /// DiscoverScreen logs engagement (view/watch/skip/save/share/follow/
    /// comment/not_relevant) either way; an empty ranked queue falls back to
    /// the chronological feed.
    static let rankedFeedEnabled = true
}
