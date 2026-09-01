# Developing Dream

Dream is a native iOS app built with SwiftUI and Supabase. This guide gets you from a fresh clone to a local build, then points out the repo conventions that matter most.

## Prerequisites

- macOS with Xcode installed.
- An iOS 26.4 simulator/runtime.
- Git.
- Optional: a Supabase account and Supabase CLI if you want to run your own backend project.

The project uses Swift 5.0 language mode and bundle id `ig.Dream`.

## Get The Code

Fork the repository on GitHub, then clone your fork:

```bash
git clone git@github.com:<your-github-user>/Dream.git
cd Dream
git remote add upstream git@github.com:dreambydreamers/Dream.git
```

Open the app:

```bash
open Dream.xcodeproj
```

Xcode resolves the Swift Package dependency on `supabase-swift`.

## Backend Options

### Use the checked-in backend config

The app has a checked-in Supabase publishable key in `Dream/Config/SupabaseConfig.swift`. Publishable anon keys are safe to ship in a client app; security is enforced by Supabase Row Level Security and RPC permissions.

This is the fastest path for UI and product work.

### Use your own Supabase project

For backend work, create a Supabase project and apply the migrations in order:

```text
supabase/migrations/0001_init.sql
...
supabase/migrations/0030_photo_comments.sql
```

Then update `Dream/Config/SupabaseConfig.swift` locally with your project URL and publishable key.

For a local stack (`supabase start`), `supabase db reset` applies all migrations and then `supabase/seed.sql`, which creates 30 fake supporters and 60 dreams shaped for inspecting the recommendation feed (seed users sign in with password `password123`). The seed refuses to run against a database with real users — never point it at a hosted project.

Storage buckets:

| Bucket | Access | Limit |
|---|---|---|
| `dream-videos` | Private | 500 MB |
| `dream-posters` | Public | 5 MB |
| `dream-images` | Public | 5 MB |
| `avatars` | Public | 2 MB |

Never commit service role keys, certificates, private keys, provisioning profiles, or local `.env` files. The `.gitignore` already blocks common secret files.

For backend details, read [supabase/README.md](supabase/README.md).

## Build

Use a concrete simulator id for reproducible command-line builds.

```bash
xcrun simctl list devices available
SIM=<simulator-udid>

xcodebuild -project Dream.xcodeproj -scheme Dream \
  -destination "id=$SIM" \
  -derivedDataPath DerivedData \
  build
```

If you build in Xcode, select the `Dream` scheme and a concrete iPhone simulator.

## Test And Verify

Three layers of verification:

**1. Ranking tests** — the recommendation ranker is a pure Swift package with a real test suite (scoring, fairness, diversity, viewer isolation, and a 7-day feed simulation through the production serving path):

```bash
cd Packages/DreamRanking
swift test
```

**2. Backend tests** — transactional pgTAP suites in `supabase/tests/` (`messaging_test.sql`, `ranking_test.sql`, `comments_test.sql`). Each runs inside one transaction and rolls back, so they are safe against a live project. Run them via psql or the Supabase MCP `execute_sql` tool; the final row must report `failures = 0`.

**3. App UI** — there is no XCTest target for the app itself; the loop is build, launch, and screenshot.

```bash
SIM=<simulator-udid>
APP=DerivedData/Build/Products/Debug-iphonesimulator/Dream.app

xcrun simctl boot "$SIM"
open -a Simulator
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" ig.Dream
xcrun simctl io "$SIM" screenshot /tmp/dream.png
```

SourceKit and IDE diagnostics can be noisy in this repo, especially around SDK selection. Trust a successful command-line build over stale editor diagnostics.

## Project Map

| Path | Purpose |
|---|---|
| `Dream/DreamApp.swift` | App entry point and launch session restore. |
| `Dream/RootView.swift` | Auth routing, tab shell, plus-button routing, global activity repository. |
| `Dream/Screens/DiscoverScreen.swift` | Vertical video feed and feed presentations. |
| `Dream/Screens/ExploreScreen.swift` | Real mixed-media Explore grid and media detail browsing. |
| `Dream/Screens/ActivityScreen.swift` | Inbox, notifications, offers, and navigation into chat. |
| `Dream/Screens/ChatScreen.swift` | Live 1:1 conversation surface. |
| `Dream/Screens/ProfileScreen.swift` | User profile, dreams, updates, saved videos, avatar/edit flows. |
| `Dream/Components` | Shared UI, feed media, compose pieces, tab bar, sharing, navigation helpers. |
| `Dream/Services` | Supabase repositories, auth, messaging, media upload/export/transcode, video preloader. |
| `Dream/Theme/DreamTheme.swift` | App colors, typography, categories, and stage presentation. |
| `Packages/DreamRanking` | Pure recommendation ranker: models, `RankingConfig` presets, pipeline, tests, simulation, `ranking-demo` CLI. |
| `supabase/migrations` | Database schema, storage, RLS, functions, search, Realtime policies, recommendation instrumentation. |
| `supabase/tests` | Transactional pgTAP suites for messaging, ranking, and comments. |
| `docs/RANKING_TUNING.md` | What every ranking weight does and how to evaluate changes. |

## Development Notes

Read [AGENTS.md](AGENTS.md) before touching core app behavior. The most important invariants are:

- Video-scoped feed state uses `Dream.feedID`, not `Dream.id`.
- Discover's virtual slot ids are only for scroll position.
- `DreamVideoBackground` must pin media layers to container bounds.
- `FeedVideoPreloader` owns signed URL caching, warm players, and feed pause/resume.
- Screens covering Discover must pause and restore the feed correctly.
- Help offers, in-app video shares, and system messages are created through Supabase RPCs.
- Explore media comes from `ExploreMediaRepository`, merging `dream_videos` with `dream_photo_updates`.
- Photo updates are uploaded through `DreamImageUploader` into `dream-images` as lowercased `{user_id}/{dream_id}/{media_id}.jpg` paths.
- Direct chat inserts from the client are plain text only.
- Storage paths must start with the lowercased user id.
- Realtime reloads, read receipts, and typing broadcasts should stay debounced or throttled.
- All ranking logic lives in `Packages/DreamRanking`; repositories only move data. Two fairness invariants must never be broken: fairness slots are filled by exposure deficit before scoring, and watch/skip signals shape only the watching viewer's own profile.
- Engagement writes go only through the `log_engagement_batch` RPC (`EngagementLogger`), never direct table inserts.
- Comment threads are per-update: keyed by `coalesce(video_id, photo_id, dream_id)` — `Dream.feedID` for a video card, the photo's own id for a photo update — and they cascade-delete with the clip or photo they hang off.
- Likes are per-clip (`dream_likes.thread_id` = `coalesce(video_id, dream_id)`, unique per viewer). Photos still like against their dream; only comments are per-photo.

## Pull Request Preflight

Before opening a PR:

```bash
xcodebuild -project Dream.xcodeproj -scheme Dream \
  -destination "id=$SIM" \
  -derivedDataPath DerivedData \
  build

# If you touched ranking code:
cd Packages/DreamRanking && swift test
```

Then include:

- What changed and why.
- What you tested.
- Screenshots for UI changes.
- Migration notes for backend changes.
- Any known follow-up work.
