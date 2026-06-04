# CLAUDE.md

Guidance for working in this repository. Read this before building features so changes match the existing architecture and conventions.

## What this app is

**Dream** is a native iOS app (SwiftUI) for sharing dreams/projects and finding people who can help build them. The core experience is a **TikTok-style vertical video feed** ("Discover") where each item is a dream with an uploaded video, author, category, stage, and "I can help" action. Backend is **Supabase** (Postgres + Auth + Storage).

- **Platform:** iOS, SwiftUI, Swift 5.0 language mode
- **Deployment target:** iOS 26.4 (`IPHONEOS_DEPLOYMENT_TARGET = 26.4`)
- **Bundle id:** `ig.Dream`
- **Backend:** Supabase project ref `qlrqcymqtxrrpekdzgxx`

## Build, run & verify

There is no test suite. Verification = build + launch in the simulator and screenshot.

```bash
# Build (use a concrete simulator id — see caveat below)
xcodebuild -project Dream.xcodeproj -scheme Dream \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Install + launch on a booted simulator
SIM=<simulator-udid>            # from `xcrun simctl list devices`
APP=/Users/ivang/Library/Developer/Xcode/DerivedData/Dream-*/Build/Products/Debug-iphonesimulator/Dream.app
xcrun simctl boot "$SIM"; open -a Simulator
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" ig.Dream

# Screenshot to verify UI
xcrun simctl io "$SIM" screenshot /tmp/dream.png
```

**Build caveats:**
- The pbxproj contains a stale **nested `Dream/Dream.xcodeproj` reference** that makes some `xcodebuild` invocations fail with *"missing its project.pbxproj file"* / *"Supported platforms ... is empty."* Work around it by always passing `-project Dream.xcodeproj` and a **concrete destination id** (`-destination 'id=<udid>'`) rather than `generic/platform=iOS`.
- **SourceKit/IDE diagnostics are unreliable here** — they frequently evaluate files against the macOS SDK and report bogus errors like *"No such module 'UIKit'"*, *"'AVAudioSession' is unavailable in macOS"*, or *"Cannot find type 'Dream' in scope"* (cross-file). **Trust `BUILD SUCCEEDED`, not the diagnostics.**

## Architecture

Plain MVVM-ish SwiftUI. Singletons for services, `ObservableObject` repositories, value-type view models.

```
DreamApp (@main)
└─ ContentView → RootView
   ├─ OnboardingScreen          (shown until RootView.signedIn = true)
   └─ MainShell (tab container) → DreamTabBar
      ├─ DiscoverScreen         (the video feed — the heart of the app)
      ├─ Explore/Activity/Profile placeholders
      └─ CreateDreamScreen      (fullScreenCover: compose + upload a dream)
```

### Directory layout (`Dream/`)
- **`DreamApp.swift`** — entry point; calls `AuthService.shared.ensureSignedIn()` on launch.
- **`RootView.swift`** — top-level routing + `MainShell` tab container + publish toast.
- **`Models/Dream.swift`** — `Dream`, `JourneyStep` view models; `DreamStage` enum.
- **`Theme/DreamTheme.swift`** — all colors, fonts, `DreamCategory` + per-category palettes, `Color(hex:)`.
- **`Screens/`** — full screens (Discover, CreateDream, DreamDetail, HelpSheet, Onboarding, placeholders).
- **`Components/`** — reusable views (ActionButton, Avatar, CategoryBadge, DreamTabBar, DreamVideoBackground, FlowLayout, JourneyTimeline, PrimaryButton, ScenePoster, VideoPicker).
- **`Services/`** — Supabase client, repos, DTOs, uploaders, auth, video preloader.
- **`Config/SupabaseConfig.swift`** — Supabase URL + publishable (anon) key. Safe to ship; security is enforced by RLS.

### Services
- **`SupabaseService.shared.client`** — the single `SupabaseClient`. Always go through this.
- **`AuthService.shared`** — `@MainActor ObservableObject`. Uses **anonymous sign-in** (`signInAnonymously`) to stub identity on simulator; designed so the anon session can later be linked to Apple Sign-In. Exposes `userId`, `isSignedIn`.
- **`DreamRepository.shared`** — `@MainActor ObservableObject`, `@Published dreams`. `loadFeed()` fetches dreams + profiles + stats + primary videos + journey steps **concurrently** (`async let`) and maps DB rows → `Dream`. `createDream(...)` inserts a row owned by the current user.
- **`DreamDTO.swift`** — `Codable` row types with `snake_case` ⇄ camelCase `CodingKeys`, plus `DreamCategory.dbValue` / `.from(dbValue:)` and `DreamStage` mappings.
- **`VideoUploader.shared`** — uploads video to private `dream-videos`, generates + uploads a poster to public `dream-posters`, inserts a `dream_videos` row, and mints signed playback URLs (`signedVideoURL`).
- **`FeedVideoPreloader.shared`** — see Video playback below.

## Backend (Supabase)

Project ref `qlrqcymqtxrrpekdzgxx`. MCP server configured in `.mcp.json` (use the `supabase` MCP tools for SQL/migrations/logs/advisors). Schema lives in `supabase/migrations/`:
- `0001_init.sql` — enums, tables, RLS policies, `dream_stats` view, triggers.
- `0002_storage.sql` — storage buckets + storage RLS.
- `0003_harden.sql` — security-advisor hardening.

### Tables (all have RLS enabled)
- **`profiles`** (1:1 with `auth.users`, auto-created via `handle_new_user` trigger) — handle, name, avatar_seed, location, skills.
- **`dreams`** — owner_id, title, description, `category` (enum), `stage` (enum), location, help_tags[], views_count.
- **`journey_steps`** — per-dream timeline (stage, date_label, note, done, sort_order).
- **`dream_videos`** — storage_path, poster_path, duration/width/height, `is_primary` (unique per dream).
- **`supporters`**, **`help_offers`** — backing + "I can help" offers.
- **`dream_stats`** (view) — derived supporters_count / offers_count.

DB enum values are short lowercase forms: category `tech/food/art/impact/education/health/music/sport`; stage `idea/early/needs/almost`. **Always map through `DreamCategory.dbValue` / `DreamStage.dbValue`** — never send the human-readable `rawValue`.

### Storage buckets
- **`dream-videos`** — **private** (500 MB limit). Playback only via **signed URLs**.
- **`dream-posters`** — public (5 MB). Thumbnails shown in feed via public URL.
- **`avatars`** — public (2 MB).

### ⚠️ Storage RLS path gotcha (important)
Object paths are namespaced by user id as the **first folder**: `{user_id}/{dream_id}/{video_id}.mp4`. Storage RLS checks `(storage.foldername(name))[1] = auth.uid()::text`, and Postgres renders `auth.uid()` **lowercase**. Swift's `UUID.uuidString` is **UPPERCASE**. **All storage paths must be lowercased** (`.uuidString.lowercased()`) or uploads/reads fail with 403/400 RLS violations. See `VideoUploader.upload`.

## Video playback system (the feed's perf-critical path)

The feed must start playback instantly while scrolling. Two cooperating types:

- **`DreamVideoBackground`** (Component) — full-bleed per-dream background. Shows poster image (or `ScenePoster` gradient fallback), then plays the looping video. Tap to pause/resume. **Pins every layer to the container bounds with a `GeometryReader` + `.frame` + `.clipped()`** — required because `scaledToFill` and `AVPlayerLayer` otherwise report the *media's* natural size for layout (clipping only affects drawing), which inflates the view and shifts the feed's overlay content off-screen. On disappear it only **pauses** (the preloader owns the player lifecycle).

- **`FeedVideoPreloader.shared`** (`@MainActor`) — keeps videos warm so playback starts fast:
  1. **Signed-URL cache** (~1h) so revisiting a dream never re-hits the network.
  2. **LRU pool** (max 4) of pre-built, pre-buffered `AVQueuePlayer`s (with `AVPlayerLooper`).
  3. **Faster startup:** `item.preferredForwardBufferDuration = 1`, `automaticallyWaitsToMinimizeStalling = false`, and a `status` KVO observer that calls `preroll(atRate:)` **only once `.readyToPlay`** (calling preroll before ready throws `NSInvalidArgumentException` — don't).
  4. **Coalesced builds** per dream id (via an in-flight `Task` map) so an early prefetch and the view's own load share one player.
  - `DiscoverScreen` calls `prefetchNeighbors(of:around:)` on first load, on index change, and on feed-count change (warms current + neighbors `[0, 1, -1, 2]`).

When touching feed/video code, preserve these invariants: bounds-pinning in `DreamVideoBackground`, status-gated preroll, build coalescing, and pause-don't-destroy on disappear.

## Conventions

- **Colors/fonts:** always use `DreamTheme` (`DreamTheme.blue`, `DreamTheme.Font.display/text`, `Color(hex:)`). Don't hardcode `Color(red:…)`.
- **Categories:** drive UI color from `dream.category.palette` (fg/bg/tint).
- **Concurrency:** services/repos that touch UI state are `@MainActor`. Use `async let` for independent Supabase fetches (see `loadFeed`).
- **Singletons:** `*.shared` for services; inject nothing — call directly.
- **Auth note:** `RootView.signedIn` is local UI state for the onboarding gate and is **separate** from `AuthService.isSignedIn` (the real Supabase session). The Supabase anon session is established at launch regardless of the onboarding screen.

## Git

`origin` has **two push URLs**, contacted in order on every `git push origin`:
1. `git@github.com:dreambydreamers/Dream.git` (primary)
2. `git@github.com:igabrilo/Dream.git`

⚠️ **Silent partial-push trap:** git pushes to both URLs but only exits non-zero on failure — a successful URL's output can hide a rejected one. If `dreambydreamers` ever **diverges** (a commit on its `video` not in your local history), its push is rejected as non-fast-forward while `igabrilo` still succeeds, so the branches drift apart unnoticed. A correct push prints **two** result blocks (one per URL). After pushing, verify parity:

```bash
git rev-parse video
git ls-remote git@github.com:dreambydreamers/Dream.git refs/heads/video | cut -f1
git ls-remote git@github.com:igabrilo/Dream.git refs/heads/video | cut -f1   # all three must match
```

If dreambydreamers is behind, push it explicitly: `git push git@github.com:dreambydreamers/Dream.git video:video`.

Main branch: `main`. Active feature branch: `video`.
