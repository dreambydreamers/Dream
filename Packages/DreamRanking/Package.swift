// swift-tools-version: 5.10
import PackageDescription

// Pure ranking logic for the Dream feed. Zero dependencies by design:
// `swift test` runs from this directory without Xcode, Supabase, or network.
let package = Package(
    name: "DreamRanking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DreamRanking", targets: ["DreamRanking"])
    ],
    targets: [
        .target(name: "DreamRanking"),
        // CLI for tuning: pipes get_feed_candidates / get_viewer_ranking_profile
        // JSON through the real ranker and prints the ordered feed with reasons.
        // Usage: swift run ranking-demo <candidates.json> <profile.json>
        .executableTarget(name: "ranking-demo", dependencies: ["DreamRanking"]),
        .testTarget(name: "DreamRankingTests", dependencies: ["DreamRanking"]),
    ]
)
