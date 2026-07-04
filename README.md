<p align="center">
  <img src="https://img.shields.io/badge/Dream-open%20source-0F7CFF?style=for-the-badge" alt="Dream is open source" />
  <img src="https://img.shields.io/badge/iOS-26.4-black?style=for-the-badge" alt="iOS 26.4" />
  <img src="https://img.shields.io/badge/SwiftUI-native-F05138?style=for-the-badge" alt="SwiftUI native app" />
  <img src="https://img.shields.io/badge/Supabase-backend-3ECF8E?style=for-the-badge" alt="Supabase backend" />
</p>

<h1 align="center">Dream</h1>

<p align="center">
  <strong>Where dreams meet the people who can build them.</strong>
</p>

<p align="center">
  Dream is an open-source iOS app for sharing dreams through short video, finding collaborators, and turning "I have an idea" into a first conversation.
</p>

<p align="center">
  <a href="#why-dream">Why Dream</a> |
  <a href="#product">Product</a> |
  <a href="#how-it-works">How It Works</a> |
  <a href="#technology">Technology</a> |
  <a href="#getting-started">Getting Started</a> |
  <a href="#contributing">Contributing</a> |
  <a href="#license">License</a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg" alt="AGPL-3.0 license" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/contributions-welcome-brightgreen.svg" alt="Contributions welcome" /></a>
</p>

---

## Why Dream

Most platforms celebrate finished things: launches, polished identities, perfect pitch decks, and final outcomes.

Dream is for the earlier, more vulnerable moment: the bakery someone has always wanted to open, the health app a nurse keeps thinking about, the children's book a retired teacher has never had help starting, the community project that needs one designer, one developer, or one brave first supporter.

The core question is simple:

> What is your dream?

Dream gives that answer a place to live, then helps the right people raise their hand and say: I can help.

## Product

Dream is built around a full-screen vertical video feed. A dream's cover clip and every update clip the owner posts each appear as their own feed card, interleaved by recency across the whole community.

| Surface | What it does |
|---|---|
| Discover | TikTok-style feed with private signed video playback, saved videos, native sharing, in-app sends, follows, dream detail, and "I can help". |
| Explore | Visual grid plus Supabase full-text search across dreams and people. |
| Activity | Messages-first inbox with notifications, help offers, unread badges, and live Realtime updates. |
| Chat | One direct 1:1 conversation per user pair, with text, shared dream videos, typing, presence, and read receipts. |
| Profile | Dreams, updates, saved videos, achievements, follows, avatar upload, profile editing, and post-update entry points. |
| Create and Update | Shared compose flow for new dreams and update clips, with on-device video transcoding before upload. |

## How It Works

Dream is a native SwiftUI app backed by Supabase. The iOS app owns the product experience; Supabase owns auth, Postgres data, row-level security, storage, Realtime, search, and workflow RPCs.

```text
DreamApp
+-- ContentView -> RootView
    +-- OnboardingScreen / AuthScreen
    +-- MainShell
        +-- DiscoverScreen
        +-- ExploreScreen
        +-- ActivityScreen
        |   +-- ChatScreen
        |   +-- DreamDetailFromIdView
        +-- ProfileScreen
        +-- + action -> CreateDreamScreen / PostUpdateScreen
```

Important directories:

| Path | Purpose |
|---|---|
| `Dream/Screens` | Full-screen SwiftUI product surfaces. |
| `Dream/Components` | Reusable UI, media, navigation, sharing, and compose pieces. |
| `Dream/Services` | Supabase repositories, auth, chat/activity, upload/export/transcode, and video preloading. |
| `Dream/Models` | App-facing value models. |
| `Dream/Theme` | Fixed light-mode colors, fonts, and category palettes. |
| `supabase/migrations` | Database schema, RLS, storage, Realtime, RPCs, search, and security hardening. |

For deeper implementation notes, read [AGENTS.md](AGENTS.md).

## Technology

| Layer | Stack |
|---|---|
| App | SwiftUI, Swift 5.0, Swift concurrency, Combine |
| Media | AVFoundation, PhotosUI, on-device video transcoding |
| Backend | Supabase Postgres, Auth, Storage, Realtime |
| Security | Row Level Security, authenticated RPC workflows, private Realtime channel policies |
| Storage | Private `dream-videos` bucket with signed URLs; public poster and avatar buckets |
| Target | iOS 26.4 |

## Getting Started

Clone the repo and open the project:

```bash
git clone git@github.com:dreambydreamers/Dream.git
cd Dream
open Dream.xcodeproj
```

Build from the command line with a concrete simulator id:

```bash
xcrun simctl list devices available
SIM=<simulator-udid>

xcodebuild -project Dream.xcodeproj -scheme Dream \
  -destination "id=$SIM" \
  -derivedDataPath DerivedData \
  build
```

There is no test suite yet. Verification is build, simulator launch, and a screenshot.

For the full developer setup, backend options, build caveats, and preflight checklist, see [DEVELOPERS.md](DEVELOPERS.md).

## Contributing

Dream is open source because the product itself is about shared effort. Developers, designers, writers, testers, and community builders are welcome.

Good first places to help:

- Improve the SwiftUI product experience.
- Tighten video playback, upload, and feed performance.
- Expand accessibility and localization.
- Improve Supabase migrations, policies, and Realtime workflows.
- Add tests and better verification scripts.
- Polish documentation for new contributors.

Before opening a pull request:

1. Search existing issues and pull requests.
2. Open an issue or discussion first for larger product changes.
3. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [DEVELOPERS.md](DEVELOPERS.md).
4. Build locally and include screenshots for UI changes.

## Community

- [Report a bug](https://github.com/dreambydreamers/Dream/issues)
- [Request a feature](https://github.com/dreambydreamers/Dream/issues)
- [Start a discussion](https://github.com/dreambydreamers/Dream/discussions)

## License

Dream is open source under the [GNU Affero General Public License v3.0](LICENSE).

That means you can use, study, modify, and share Dream. If you run a modified version over a network, the AGPL requires you to make the corresponding source code available under the same license.

---

<p align="center">
  <strong>Everyone has a dream worth pursuing. Let's build the place where they begin.</strong>
</p>
