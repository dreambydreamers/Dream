# Dream

Dream is a native iOS app for sharing dreams, projects, and the work people need help bringing to life. The core experience is a full-screen vertical video feed: every dream cover clip and every update clip becomes its own feed card, interleaved by recency across the whole community.

The backend is Supabase: Postgres, Auth, Storage, Realtime, RLS, and RPC workflows for help offers, chat, in-app video sharing, search, and notifications.

## Current App

- **Discover** — TikTok-style vertical video feed with signed private video playback, cached posters, save/bookmark, native export/share, in-app send, follow, dream detail, and "I can help".
- **Explore** — Instagram-style grid plus debounced Supabase full-text search for people and dreams.
- **Activity** — messages-first inbox with notifications, help offers, unread badges, and live Realtime updates.
- **Chat** — one 1:1 conversation per user pair, with text messages, shared dream videos, typing, presence, read receipts, and shared-video detail navigation.
- **Profile** — dreams, updates, saved videos, achievements, follow state, avatar upload, edit profile, and post-update entry points.
- **Create / Update** — shared compose UI for new dreams and update clips, with on-device video transcoding before upload.

## Tech Stack

| Layer | Technology |
|---|---|
| iOS | SwiftUI, Swift concurrency, Combine, AVFoundation, PhotosUI |
| Backend | Supabase Postgres, Auth, Storage, Realtime |
| Database security | Row Level Security, authenticated RPC workflows, private Realtime channel policies |
| Media | Private `dream-videos` bucket with signed URLs, public poster/avatar buckets |
| Deployment target | iOS 26.4 |

## Architecture

```text
DreamApp
└─ ContentView -> RootView
   ├─ OnboardingScreen / AuthScreen
   └─ MainShell
      ├─ DiscoverScreen
      ├─ ExploreScreen
      ├─ ActivityScreen
      │  ├─ ChatScreen
      │  └─ DreamDetailFromIdView
      ├─ ProfileScreen
      └─ + action -> CreateDreamScreen / PostUpdateScreen
```

Important folders:

- `Dream/Screens` — full-screen SwiftUI surfaces.
- `Dream/Components` — reusable UI and media components such as `DreamTabBar`, `PosterImage`, `FollowButton`, `DreamVideoBackground`, `InAppShareSheet`, `MediaVideoPlayer`, and `VideoCompose`.
- `Dream/Services` — Supabase repositories, auth, chat/activity repos, media upload/export/transcode, and feed preloading.
- `Dream/Models` — app-facing value models.
- `Dream/Theme` — fixed light-mode colors, fonts, and category palettes.
- `supabase/migrations` — schema, RLS, storage, Realtime, RPCs, search, and security hardening.

## Backend Notes

Apply Supabase migrations in order through `0019_security_hardening.sql`.

Key backend conventions:

- Videos are private and played through signed URLs.
- Storage paths must start with lowercased user ids.
- All cross-user workflow writes go through RPCs.
- Help offers, video shares, and plain messages between the same two people share one direct conversation.
- Direct client message inserts are plain text only; system/share messages are created by RPCs or triggers.
- Chat Realtime uses private `conversation:<uuid>` channels.

See `supabase/README.md` for backend details and `AGENTS.md` for deeper implementation guidance.

## Build

There is no test suite yet. Verification is build, simulator launch, and screenshot.

```bash
xcodebuild -project Dream.xcodeproj -scheme Dream \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

If command-line builds act strange, use a concrete simulator id and keep `-project Dream.xcodeproj`; the project currently contains a stale nested project reference that can confuse generic destinations.

## Git

Main branch: `main`

Primary remote: `git@github.com:dreambydreamers/Dream.git`

## License

Open source under [AGPL-3.0](LICENSE).
