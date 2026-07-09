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
supabase/migrations/0020_explore_photo_updates.sql
```

Then update `Dream/Config/SupabaseConfig.swift` locally with your project URL and publishable key.

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

## Launch And Verify

There is no test suite yet. The current verification loop is build, launch, and screenshot.

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
| `supabase/migrations` | Database schema, storage, RLS, functions, search, Realtime policies. |

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

## Pull Request Preflight

Before opening a PR:

```bash
xcodebuild -project Dream.xcodeproj -scheme Dream \
  -destination "id=$SIM" \
  -derivedDataPath DerivedData \
  build
```

Then include:

- What changed and why.
- What you tested.
- Screenshots for UI changes.
- Migration notes for backend changes.
- Any known follow-up work.
