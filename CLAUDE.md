# CLAUDE.md

Guidance for working in this repository. Read this before building features so changes match the existing architecture and conventions.

## What this app is

**Dream** is a native iOS app (SwiftUI) for sharing dreams/projects and finding people who can help build them. The core experience is a **TikTok-style vertical video feed** ("Discover"). Each feed card is **one video** belonging to a dream — a dream's cover clip *and* every "update" clip the owner posts each surface as their own card, interleaved across all dreams by recency, carrying the dream's author/category/stage and the "I can help" action. Backend is **Supabase** (Postgres + Auth + Storage).

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
   ├─ OnboardingScreen          (shown until AuthService.isSignedIn)
   └─ MainShell                 → paged TabView (swipeable) + floating DreamTabBar overlay
      ├─ DiscoverScreen         (the video feed — the heart of the app)
      ├─ Explore/Activity placeholders
      ├─ ProfileScreen          (current user, or any author opened from the feed)
      └─ "+" → CreateDreamScreen (new dream)  ·  PostUpdateScreen (update clip)
```

`MainShell` lays out the four tab screens in a **horizontally-paged `TabView`** (`.tabViewStyle(.page(indexDisplayMode: .never))`, selection bound to `activeTab`), with the floating `DreamTabBar` overlaid at the bottom of a `ZStack`. So tabs are reachable **both** by tapping the bar and by **swiping left/right** between adjacent tabs (order: Discover → Explore → Activity → Profile). See **Navigation & gestures** below.

The **"+" tab button** routes based on whether the user already has a dream (`DreamRepository.myDream()`): no dream → `CreateDreamScreen`; has a dream → a confirmation dialog offering **"Post an update"** (`PostUpdateScreen`) or **"Start a new dream"** (`CreateDreamScreen`). The same `PostUpdateScreen` is also reachable from the "Post an update" button on the owner's `ProfileScreen`. "+" is an **action, not a page** — it is not a TabView tag, just a button in the bar.

### Directory layout (`Dream/`)
- **`DreamApp.swift`** — entry point; calls `AuthService.shared.ensureSignedIn()` on launch.
- **`RootView.swift`** — top-level routing + `MainShell` tab container + "+" routing + publish/update toast.
- **`Models/Dream.swift`** — `Dream`, `JourneyStep` view models; `DreamStage` enum. `Dream` is one *video card* (see `feedID`, `displayTitle`, `videoId`, `videoTitle`).
- **`Theme/DreamTheme.swift`** — all colors, fonts, `DreamCategory` + per-category palettes, `Color(hex:)`.
- **`Screens/`** — full screens (Discover, CreateDream, **PostUpdate**, DreamDetail, HelpSheet, Profile, EditProfile, Auth, Onboarding, placeholders).
- **`Components/`** — reusable views (ActionButton, Avatar, CategoryBadge, **DreamTabBar**, DreamVideoBackground, FlowLayout, **InteractiveBackSwipe**, JourneyTimeline, MediaVideoPlayer, PrimaryButton, ScenePoster, VideoPicker, **VideoCompose**). `VideoCompose.swift` holds the shared compose pieces (`loadVideoThumbnail`, `VideoSourceCard`, `VideoPreviewCard`, `.videoSourcePicker(...)`) used by **both** CreateDream and PostUpdate — keep new compose UI here rather than duplicating it. `DreamTabBar` is a **floating translucent capsule** (icon-only, animated active highlight via `matchedGeometryEffect`, blue accent "+"); `InteractiveBackSwipe.swift` holds the `.interactiveBackSwipe(...)` / `ConditionalBackSwipe` edge-swipe-back modifiers — see **Navigation & gestures**.
- **`Services/`** — Supabase client, repos (`DreamRepository`, `ProfileRepository`), DTOs, uploaders, auth, video preloader.
- **`Config/SupabaseConfig.swift`** — Supabase URL + publishable (anon) key. Safe to ship; security is enforced by RLS.

### Services
- **`SupabaseService.shared.client`** — the single `SupabaseClient`. Always go through this.
- **`AuthService.shared`** — `@MainActor ObservableObject`. Uses **anonymous sign-in** (`signInAnonymously`) to stub identity on simulator; designed so the anon session can later be linked to Apple Sign-In. Exposes `userId`, `isSignedIn`.
- **`DreamRepository.shared`** — `@MainActor ObservableObject`, `@Published dreams`. A shared `fetchContext(_:)` loads profiles + stats + **all** videos + journey steps **concurrently** (`async let`), then two mappers consume it:
  - `loadFeed()` → `enrichFeed(...)` emits **one card per video** (cover + updates), interleaved across dreams by the video's `created_at` desc; dreams with no video still emit one (gradient) card.
  - `dreams(ownedBy:)` → `enrich(...)` emits **one card per dream** using its primary video (used by the profile).
  - Also: `createDream(...)`, `myDream()` (the user's featured-or-latest dream, the update target), `setFeatured(...)`, `videos(forDream:)` → `[DreamMedia]`.
- **`ProfileRepository.shared`** — profile fetch, `stats` (`profile_stats` view), profile edit, follow/unfollow.
- **`DreamDTO.swift`** — `Codable` row types with `snake_case` ⇄ camelCase `CodingKeys`, plus `DreamCategory.dbValue` / `.from(dbValue:)` and `DreamStage` mappings. `DreamVideoDTO` carries `title` (per-video heading) and `createdAt`.
- **`VideoUploader.shared`** — `upload(localVideoURL:dreamId:markPrimary:title:)` uploads the video to private `dream-videos`, generates + uploads a poster to public `dream-posters`, and inserts a `dream_videos` row. `markPrimary: false` + a `title` is how an **update clip** is posted; the cover video uses `markPrimary: true` and `title: nil`. Also mints signed playback URLs (`signedVideoURL`).
- **`FeedVideoPreloader.shared`** — warm-player pool + signed-URL cache **and** the cross-screen feed pause/resume API (`feedActiveID`, `pauseFeedPlayer()`/`resumeFeedPlayer()` with `feedCoverDepth`, `feedMuted`, `.pausesDiscoverFeed()`). See Video playback below.

## Backend (Supabase)

Project ref `qlrqcymqtxrrpekdzgxx`. MCP server configured in `.mcp.json` (use the `supabase` MCP tools for SQL/migrations/logs/advisors). Schema lives in `supabase/migrations/`:
- `0001_init.sql` — enums, tables, RLS policies, `dream_stats` view, triggers.
- `0002_storage.sql` — storage buckets + storage RLS.
- `0003_harden.sql` — security-advisor hardening.
- `0004_profile_from_metadata.sql` — populate profile handle/name from sign-up metadata.
- `0005_videos_readable_by_all_authed.sql` — relax `dream-videos` SELECT so any authed user can play any video (cross-user feed playback).
- `0006_profile_features.sql` — `follows`, featured dream (`dreams.is_featured`, partial-unique per owner), `profile_stats` view.
- `0007_video_title.sql` — `dream_videos.title` (per-video heading for update clips).

### Tables (all have RLS enabled)
- **`profiles`** (1:1 with `auth.users`, auto-created via `handle_new_user` trigger) — handle, name, avatar_seed, location, skills.
- **`dreams`** — owner_id, title, description, `category` (enum), `stage` (enum), location, help_tags[], views_count, `is_featured` (one pinned "main" dream per owner; partial-unique).
- **`journey_steps`** — per-dream timeline (stage, date_label, note, done, sort_order).
- **`dream_videos`** — storage_path, poster_path, duration/width/height, `is_primary` (unique per dream — the cover clip), `title` (per-video heading; null on the cover clip), created_at. A dream has **many** videos (cover + updates).
- **`follows`** — follower_id / followed_id.
- **`supporters`**, **`help_offers`** — backing + "I can help" offers.
- **`dream_stats`** (view) — derived supporters_count / offers_count. **`profile_stats`** (view) — videos/followers/following/offers counts.

DB enum values are short lowercase forms: category `tech/food/art/impact/education/health/music/sport`; stage `idea/early/needs/almost`. **Always map through `DreamCategory.dbValue` / `DreamStage.dbValue`** — never send the human-readable `rawValue`.

### Storage buckets
- **`dream-videos`** — **private** (500 MB limit). Playback only via **signed URLs**.
- **`dream-posters`** — public (5 MB). Thumbnails shown in feed via public URL.
- **`avatars`** — public (2 MB).

### ⚠️ Storage RLS path gotcha (important)
Object paths are namespaced by user id as the **first folder**: `{user_id}/{dream_id}/{video_id}.mp4`. Storage RLS checks `(storage.foldername(name))[1] = auth.uid()::text`, and Postgres renders `auth.uid()` **lowercase**. Swift's `UUID.uuidString` is **UPPERCASE**. **All storage paths must be lowercased** (`.uuidString.lowercased()`) or uploads/reads fail with 403/400 RLS violations. See `VideoUploader.upload`.

## Video playback system (the feed's perf-critical path)

The feed must start playback instantly while scrolling. Two cooperating types:

- **`DreamVideoBackground`** (Component) — full-bleed per-card background. Shows poster image (or `ScenePoster` gradient fallback), then plays the looping video. Tap to pause/resume. **Pins every layer to the container bounds with a `GeometryReader` + `.frame` + `.clipped()`** — required because `scaledToFill` and `AVPlayerLayer` otherwise report the *media's* natural size for layout (clipping only affects drawing), which inflates the view and shifts the feed's overlay content off-screen. On disappear it only **pauses** (the preloader owns the player lifecycle).

- **`FeedVideoPreloader.shared`** (`@MainActor`) — keeps videos warm so playback starts fast:
  1. **Signed-URL cache** (~1h) so revisiting a card never re-hits the network.
  2. **LRU pool** (max 4) of pre-built, pre-buffered `AVQueuePlayer`s (with `AVPlayerLooper`).
  3. **Faster startup:** `item.preferredForwardBufferDuration = 1`, `automaticallyWaitsToMinimizeStalling = false`, and a `status` KVO observer that calls `preroll(atRate:)` **only once `.readyToPlay`** (calling preroll before ready throws `NSInvalidArgumentException` — don't).
  4. **Coalesced builds** per card (via an in-flight `Task` map) so an early prefetch and the view's own load share one player.
  - `DiscoverScreen` calls `prefetchNeighbors(of:around:)` on first load, on index change, and on feed-count change (warms current + neighbors `[0, 1, -1, 2]`).

### ⚠️ Cards are keyed by `feedID`, not dream id (important)
Because one dream can produce several feed cards (cover + updates), all **video-scoped** state must key on **`Dream.feedID`** (`= videoId ?? id`), **not** `dream.id` — otherwise two cards of the same dream collide on one player / signed URL (the wrong clip plays). This applies to: the preloader's `players`/`signedURLs`/`building`/`statusObservers` maps, `DreamVideoBackground`'s `.task(id:)`, and `DiscoverScreen`'s `.id(...)` on the background. Use `dream.id`/`dream.ownerId` only for navigation (open the dream detail / author profile). Show the card's heading with **`dream.displayTitle`** (`videoTitle ?? title`).

When touching feed/video code, preserve these invariants: **per-video `feedID` keying**, bounds-pinning in `DreamVideoBackground`, status-gated preroll, build coalescing, and pause-don't-destroy on disappear.

### Feed pause/resume across covering screens
A screen presented **over** the feed (detail, profile, help sheet, create/update) freezes the presenter, so the feed view can't pause itself. The preloader exposes **`pauseFeedPlayer()` / `resumeFeedPlayer()`**, balanced by an internal **`feedCoverDepth`** counter so the feed only resumes once the **outermost** cover closes (nested covers are safe). `resumeFeedPlayer()` defers a runloop tick (so it lands after the covering view's own `onDisappear`) and restores `feedMuted`.
- `DiscoverScreen` publishes which card is on screen via **`feedActiveID`** (the `feedID`), set in `.task`, on index/feed-count change, **and on `.onAppear`** — the `onAppear` re-mark is required because the feed view now persists inside the paged `TabView` (so `.task` won't re-fire when you page back). On the feed's own `onDisappear` it sets `feedActiveID = nil`.
- Any screen presented over the feed adopts **`.pausesDiscoverFeed()`** (a one-liner modifier in `FeedVideoPreloader.swift` that calls pause on appear / resume on disappear). Applied to `HelpSheet` and the "+" `CreateDreamScreen`/`PostUpdateScreen` covers; `DreamDetailScreen` and the pushed `ProfileScreen` call pause/resume directly in their own `onAppear`/`onDisappear`.

## Navigation & gestures

Three cooperating gesture systems sit on top of the feed — when editing any of them, keep the others working:

- **Horizontal tab paging.** `MainShell`'s content is a paged `TabView(selection: $activeTab)`. Because the feed needs its **own vertical** swipe (card-to-card paging), `DiscoverScreen`'s feed drag is a **`.simultaneousGesture`** guarded to vertical-only (`abs(height) > abs(width)`) so horizontal swipes fall through to the `TabView` for tab switching while vertical swipes page the feed. Don't convert it back to `.gesture` or drop the axis guard or horizontal tab swipes break on Discover.
- **Tab bar collapse.** `DreamTabBar` takes a `collapsed: Binding<Bool>`; when true it scales down (`scaleEffect(... anchor: .bottom)`) and dims. `DiscoverScreen` sets `tabBarCollapsed = true` on a vertical feed swipe; any tap on the bar (a tab **or** "+") sets it back to false, and `MainShell` resets it on `activeTab` change. **All** collapse/expand transitions route through a single `.animation(.smooth(...), value: collapsed)` modifier — set `collapsed` *outside* `withAnimation` so taps animate with the same smooth curve (don't wrap it in a separate spring). **Scale must wrap the fully-assembled pill** (after `.background`/`.clipShape`/`.shadow`), not the inner `HStack`, or only the icons shrink and the capsule background stays full size.
- **Edge-swipe back.** Covers have no native interactive dismiss, so `.interactiveBackSwipe(slideOff:_:)` (in `InteractiveBackSwipe.swift`) adds a left-edge strip that tracks a rightward drag and dismisses past a distance/velocity threshold. The strip is inset top/bottom so it never swallows a top-left back button or bottom CTA, and is narrow (24pt) so it doesn't block interior vertical scrolling. `slideOff: true` (default) slides the screen off-screen before `onBack` (native cover-dismiss feel); **`slideOff: false`** springs back in place and is for **popping a step within a still-mounted screen**. Applied to `DreamDetailScreen` (always) and `ProfileScreen` (only when pushed over the feed, via `ConditionalBackSwipe` keyed on `onBack != nil`).
  - **Multi-step sheets own their back logic.** `HelpSheet` ("I can help" / "Offer your help") is a multi-step flow driven by an internal `mode` (`.pick` → `.configure`/`.review`). Its back-swipe lives **inside** the sheet (`.interactiveBackSwipe(slideOff: false) { goBack() }`) so it **steps back to `.pick` before closing** the sheet, mirroring the in-flow "Back" button — not bolted on at the presentation site (which would always dismiss the whole sheet). When a presented screen has its own internal navigation, give it `slideOff: false` and let it decide pop-vs-dismiss.

## Conventions

- **Colors/fonts:** always use `DreamTheme` (`DreamTheme.blue`, `DreamTheme.Font.display/text`, `Color(hex:)`). Don't hardcode `Color(red:…)`.
- **Categories:** drive UI color from `dream.category.palette` (fg/bg/tint).
- **Concurrency:** services/repos that touch UI state are `@MainActor`. Use `async let` for independent Supabase fetches (see `loadFeed`).
- **Singletons:** `*.shared` for services; inject nothing — call directly.
- **Compose UI:** the new-dream and update flows (`CreateDreamScreen`, `PostUpdateScreen`) share their source cards, preview, thumbnail and pickers via `Components/VideoCompose.swift`. Reuse those rather than re-implementing — only each screen's unique fields (full dream form vs. a single heading) live in the screen.
- **Tab bar:** the bottom nav is the floating `DreamTabBar` capsule, overlaid by `MainShell` (it does **not** push content up). New tabs go through it + a new `TabView` page/tag in `MainShell.tabContent`. Any screen presented over the feed should pause the feed video (`.pausesDiscoverFeed()` or direct pause/resume) and, if dismissable, use `.interactiveBackSwipe`.
- **Auth note:** `RootView` gates the onboarding screen on `AuthService.isSignedIn` (the real Supabase session). The Supabase **anonymous** session is established at launch (`ensureSignedIn()`) regardless, so the user is authed even before Apple Sign-In.

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

Main branch: `main`. Active feature branch: `dev` (the parity check above applies to whichever branch you push — substitute its name for `video`).
