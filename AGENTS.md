# AGENTS.md

Guidance for working in this repository. Read this before building features so changes match the existing architecture and conventions.

## What this app is

**Dream** is a native iOS app (SwiftUI) for sharing dreams/projects and finding people who can help build them. The core experience is a **TikTok-style vertical video feed** ("Discover") ranked by a **two-sided matching algorithm** whose success metric is successful connections (help offers → conversations → delivered support), not watch time — see the "Recommendation system" section. Each feed card is **one video** belonging to a dream, carrying the dream's author/category/stage, per-clip comments, and the "I can help" action. Backend is **Supabase** (Postgres + Auth + Storage).

- **Platform:** iOS, SwiftUI, Swift 5.0 language mode
- **Deployment target:** iOS 26.4 (`IPHONEOS_DEPLOYMENT_TARGET = 26.4`)
- **Bundle id:** `ig.Dream`
- **Backend:** Supabase project ref `ohmtchfldrqobwrtyhmz`

## Build, run & verify

Three verification layers:

1. **Ranking unit tests** (pure Swift, no network): `cd Packages/DreamRanking && swift test` — 26 tests incl. a 7-day feed simulation through the production serving path.
2. **Backend SQL tests** (pgTAP, transactional + rollback — safe on the hosted project): run `supabase/tests/messaging_test.sql`, `ranking_test.sql`, `comments_test.sql` via the Supabase MCP `execute_sql` tool or psql; the final row must report `failures = 0`.
3. **App**: build + launch in the simulator and screenshot (no XCTest target for the app itself).

```bash
# Build (use a concrete simulator id)
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

**Build caveat:**
- **SourceKit/IDE diagnostics are unreliable here** — they frequently evaluate files against the macOS SDK and report bogus errors like *"No such module 'UIKit'"*, *"'AVAudioSession' is unavailable in macOS"*, or *"Cannot find type 'Dream' in scope"* (cross-file). **Trust `BUILD SUCCEEDED`, not the diagnostics.**

## Architecture

Plain MVVM-ish SwiftUI. Singletons for services, `ObservableObject` repositories, value-type view models.

```
DreamApp (@main)                (no forced color scheme — every token is dynamic, see Conventions)
└─ ContentView → RootView
   ├─ OnboardingScreen          (shown until AuthService.isSignedIn; AuthScreen = email/password)
   └─ MainShell                 → paged TabView (swipeable) + floating DreamTabBar overlay
      ├─ DiscoverScreen         (the video feed — the heart of the app)
      ├─ ExploreScreen          (real Instagram-style media grid + Supabase full-text search)
      ├─ ActivityScreen         (notifications + conversations + help offers, live over Realtime)
      │   ├─ ChatScreen         (1:1 live chat — typing, presence, read receipts, video shares)
      │   └─ DreamDetailFromIdView  (dream detail opened by tapping a shared video in chat)
      ├─ ProfileScreen          (current user or any author; 3 tabs: Dreams / Updates / Saved)
      └─ "+" → CreateDreamScreen (new dream)  ·  PostUpdateScreen (photo/video update)
```

`MainShell` lays out the four tab screens in a **horizontally-paged `TabView`** (`.tabViewStyle(.page(indexDisplayMode: .never))`, selection bound to `activeTab`), with the floating `DreamTabBar` overlaid at the bottom of a `ZStack`. So tabs are reachable **both** by tapping the bar and by **swiping left/right** between adjacent tabs (order: Discover → Explore → Activity → Profile). See **Navigation & gestures** below.

The **"+" tab button** routes based on whether the user already has a dream (`DreamRepository.myDream()`): no dream → `CreateDreamScreen`; has a dream → a confirmation dialog offering **"Post an update"** (`PostUpdateScreen`) or **"Start a new dream"** (`CreateDreamScreen`). The same `PostUpdateScreen` is also reachable from the "Post an update" button on the owner's `ProfileScreen`. "+" is an **action, not a page** — it is not a TabView tag, just a button in the bar.

### Directory layout (`Dream/`)
- **`DreamApp.swift`** — entry point; registers the fonts (`DreamFonts.register()`) and calls `AuthService.shared.restoreSession()` on launch. It deliberately sets **no** `.preferredColorScheme` — the app follows the system and every `DreamTheme` token is dynamic (see Conventions).
- **`RootView.swift`** — top-level routing + `MainShell` tab container + "+" routing + publish/update toast. `MainShell` holds `ActivityRepository.shared` so the tab-bar unread badge stays live even off the Activity tab.
- **`Models/Dream.swift`** — `Dream`, `JourneyStep` view models; `DreamStage` enum. `Dream` is one *video card* (see `feedID`, `displayTitle`, `displayDescription`, `videoId`, `videoTitle`, `videoCaption`).
- **`Theme/DreamTheme.swift`** — all colors, fonts, `DreamCategory` + per-category palettes, `Color(hex:)`. **Every theme color is a dynamic `Color(light:dark:)`** that resolves against the current trait collection (see Conventions → dark mode); `Theme/DreamTokens.swift` holds the spacing/radius/shadow/motion scales.
- **`Screens/`** — full screens (Discover, CreateDream, **PostUpdate**, DreamDetail, HelpSheet, Profile, EditProfile, Auth, Onboarding, **Activity**, **Chat**, placeholders).
- **`Components/`** — reusable views (ActionButton, Avatar, CategoryBadge, **DreamAchievements**, **DreamTabBar**, DreamVideoBackground, **EyebrowLabel**, FlowLayout, **FollowButton**, **GlassCircleButton**, **InAppShareSheet**, **InteractiveBackSwipe**, JourneyTimeline, MediaVideoPlayer, **PosterImage**, PrimaryButton, ScenePoster, **ShareSheet**, **StatCell**, **ThreeColumnGrid**, VideoPicker, **VideoCompose**). `VideoCompose.swift` holds the shared compose pieces (`loadVideoThumbnail`, `VideoSourceCard`, `VideoPreviewCard`, `PhotoPreviewCard`, `.videoSourcePicker(...)`) used by **both** CreateDream and PostUpdate — keep new compose UI here rather than duplicating it. `PosterImage` is the shared cached remote-poster loader; use it for feed/share/detail/profile/explore thumbnails instead of ad hoc `AsyncImage`. `FollowButton`, `GlassCircleButton`, `StatCell`, `EyebrowLabel`, and `ThreeColumnGrid` centralize repeated UI treatments. `InAppShareSheet` is the Instagram-style send-to-friend sheet for sharing feed videos into direct chats. `DreamTabBar` is a **floating translucent capsule** (icon-only, animated active highlight via `matchedGeometryEffect`, blue accent "+", optional unread `badge`); `InteractiveBackSwipe.swift` holds the `.interactiveBackSwipe(...)` / `ConditionalBackSwipe` edge-swipe-back modifiers — see **Navigation & gestures**.
- **`Services/`** — Supabase client, repos (`DreamRepository`, `ExploreMediaRepository`, `ProfileRepository`, `ActivityRepository`, `ChatRepository`, `HelpOfferRepository`, `VideoShareRepository`, `CommentRepository`, `LikeRepository`, `RecommendationRepository`), recommendation plumbing (`FeedQueueService`, `EngagementLogger`), DTOs (`DreamDTO`, `MessagingDTO`, `RankingDTO`), uploaders/exporters (`AvatarUploader`, `DreamImageUploader`, `VideoUploader`, `VideoTranscoder`, `VideoExporter`), auth, video preloader.
- **`Config/`** — `SupabaseConfig.swift` (URL + publishable anon key; safe to ship, security is RLS) and `FeatureFlags.swift` (`rankedFeedEnabled`).
- **`Packages/DreamRanking/`** (repo root, sibling of `Dream/`) — the pure, zero-dependency ranking package: models, `RankingConfig` presets, `DreamRanker`, tests + 7-day simulation, and the `ranking-demo` CLI. See "Recommendation system".

### Discover screen features (`DiscoverScreen.swift`)
Beyond the core video feed:
- **Ranked serving + engagement logging**: cards come from the recommendation queue (`DreamRepository.loadFeed()` → ranked path, chronological fallback); the screen logs `view`/watch-time/`save`/`follow`/`not_relevant` events — see "Recommendation system" for the rules that must not break (one `view` per dream per session; skips only shape the skipper's own profile).
- **Per-clip comments**: the bubble `ActionButton` opens `CommentsSheet` for the card's clip thread (count badge from `Dream.comments`, live overrides keyed by `feedID`).
- **Per-clip likes**: the rail's heart toggles through `LikesStore` (optimistic, haptic), counts enriched onto `Dream.likes` by `DreamRepository` and overridden live by the store.
- **Endless vertical paging**: the feed uses SwiftUI's paged vertical `ScrollView` with repeated **virtual slots** (`currentSlot: Int?`, `feedCycleCount`, `feedResetToken`) so scrolling past the last video continues back to the first. The virtual slot is only a scroll identity; real video state still keys on `dream.feedID`.
- **Loop normalization**: when the user reaches an edge copy of the virtual feed, `normalizeLoopSlotIfNeeded()` silently snaps back to the middle copy of the same real video with animations disabled. Do not replace this with real duplicated dreams or duplicate player/cache keys.
- **Presentation restore**: every Discover sheet/cover (`DreamDetailScreen`, `HelpSheet`, `InAppShareSheet`, pushed `ProfileScreen`) uses `restoreFeedAfterPresentation`. It restores `activeTab = .discover`, recenters the current video on its middle virtual slot, and changes `feedResetToken` to rebuild the paged scroll view. This prevents the "two videos visible" bug after dismissing the share sheet.
- **Inactive virtual cards are visual-only**: card chrome (title, author row, buttons, gradients) renders only for the centered active slot. Neighboring virtual copies may be partly visible during paging/restore, but must not show duplicate controls.
- **Double-tap to like**: `DreamVideoBackground(onDoubleTap:)` pops a centered heart and calls back; Discover and Explore both pass a handler that only ever *likes* (never unlikes — the gesture is too imprecise to undo with). Single tap still pauses; the two-tap recognizer is attached first so it wins.
- **Bookmark (Save)**: bookmark icon saves/unsaves the current dream to `SavedDreamsStore`. Filled icon = saved. Haptic feedback on toggle.
- **Three-dots menu**: `confirmationDialog` with "Save to Gallery" (system photo export), "Share outside Dream" (native share sheet) via `VideoActionsModel`, and "Not interested" (logs `not_relevant`, hides the dream locally, dismisses it server-side for this viewer).
- **Expandable description**: description text truncates at 2 lines with a tappable "more" label that expands to full text. State keyed on `feedID` via `expandedDesc: Set<UUID>`.

### Explore screen features (`ExploreScreen.swift`)
Explore is a real mixed-media grid, not mocked placeholder content.
- **Source of truth:** `ExploreMediaRepository.shared.loadFeed()` merges `dream_videos` (cover + update videos) with `dream_photo_updates` (photo updates), enriches them with dream/profile/stats/timeline data, and orders the grid **through the ranker with `RankingConfig.explore`** (fresh + interests first; dismissed dreams hidden; recency fallback on failure) — see "Recommendation system".
- **Grid:** use `ThreeColumnGrid`, `ExploreMediaGridCell`, real poster/photo URLs, video play badges, and author handle overlays. Do not reintroduce gradient mock posts.
- **Video detail:** opening a video uses a full-screen, Discover-like vertical pager. Only the active page mounts `DreamVideoBackground`; inactive pages are poster-only so adjacent videos do not overlap or play during scroll.
- **Photo detail:** opening a photo uses a black Instagram-style detail page with the photo hero, author/actions/context, and "More to explore" related media. Related videos can transition into the video pager.
- **Actions:** video "Send" opens `InAppShareSheet`; video "More" uses `VideoActionsModel` for gallery/native export. Photo share uses the native `ShareSheet` for the public image URL; photo help/view-dream actions stay in-app.
- **Likes & comments:** both detail surfaces carry the same engagement as Discover — a like (`LikesStore`) and a comment thread (`CommentsSheet`). A video item's `id` **is** its `dream_videos.id`, so an Explore like/comment and a Discover one on the same clip are the same thread. **Comments key per item** (`commentThread(for:)` = the item's own id), so each photo of a dream has its own thread; **likes on photos still key on the dream** (`likeThread(for:)`), because `dream_likes` has no `photo_id`. Counts load once per sheet presentation alongside the likes fetch.
- **Video pauses under covers:** the pager passes `isCovered` (any of the comments/help/share/more/export presentations) into `DreamVideoBackground(isPaused:)`, so the clip stops instead of playing and talking behind a sheet. Keep new presentations in that computed flag.
- **Debug entry:** `--explore-open=<video|photo>` opens the first matching item in the full-screen viewer at launch (pair with `--initial-tab=explore`) — the simulator can't be scripted to tap a grid cell.
- **Search focus:** `ExploreScreen` receives `isSearchFocused` from `RootView`; `MainShell` hides the floating tab bar while the search field is focused so the keyboard never lifts the bar over the input.

### Services
- **`SupabaseService.shared.client`** — the single `SupabaseClient`. Always go through this.
- **`AuthService.shared`** — `@MainActor ObservableObject`. **Email + password** auth (`signIn`/`signUp`/`signOut`); `restoreSession()` on launch restores any persisted session. ⚠️ **`signOut()` must tear down every per-user singleton** via `resetLocalState()` (also fired from `apply(session:)` when the user id changes without an explicit sign-out). These singletons outlive a session, so anything cached in them leaks into the *next* account on the same device — feed, likes, saved cards, notifications, buffered engagement events, and signed video URLs that stay valid ~1 h. **When you add a singleton holding per-user state, add its `reset()` to `resetLocalState()`.** Subscribes to `auth.authStateChanges` and exposes `userId`, `isSignedIn`, `isBusy`, `errorMessage`, and `awaitingEmailConfirmation` (set when sign-up succeeds but the project requires email confirmation, so no session is returned). `AuthScreen` drives this.
- **`DreamRepository.shared`** — `@MainActor ObservableObject`, `@Published dreams`. A shared `fetchContext(_:)` loads profiles + stats + **all** videos + journey steps + per-thread comment counts **concurrently** (`async let`), then the mappers consume it:
  - `loadFeed()` → **ranked path** (`loadRankedFeed()`: queue ids → seen-aware clip pick → one card per dream in queue order) with `loadChronologicalFeed()` fallback → `enrichFeed(...)` emitting **one card per video** interleaved by recency; dreams with no video still emit one (gradient) card.
  - `dreams(ownedBy:)` → `enrich(...)` emits **one card per dream** using its primary video (used by the profile).
  - Also: `hideDream(_:)` ("Not interested" local removal), `createDream(...)`, `myDream()` (the user's featured-or-latest dream, the update target), `setFeatured(...)`, `videos(forDream:)` → `[DreamMedia]`.
- **`ProfileRepository.shared`** — `@MainActor ObservableObject` for profile fetch, batch `profiles(ids:)`, `stats` (`profile_stats` view), profile edit, avatar URL update, follow/unfollow, and `followingProfiles()` for in-app share recipients. It publishes `lastError` for user-visible failures.
- **`ActivityRepository.shared`** — `@MainActor ObservableObject`, **app-wide singleton** (`start()` once signed in; keep it alive — the tab-bar badge depends on it, do **not** `stop()` on tab leave). Aggregates `notifications` + `conversations` + `offersMade`/`offersReceived`, publishes `lastError`, and keeps a live `unreadCount` via a `notifications` Realtime channel. See Messaging & Activity below.
- **`ChatRepository`** — **one instance per open `ChatScreen`** (`start()` on appear, `stop()` on disappear). Drives a single conversation: bounded newest-first history fetch, send, share-preview hydration for `dream_share` messages, and a private `conversation:{id}` Realtime channel (`isPrivate = true`) for message inserts, read-receipt updates, typing broadcast, and presence. See Messaging & Activity below.
- **`HelpOfferRepository.shared`** — thin RPC client for the help-offer workflow: `createOffer` (`create_help_offer`), `respond` (`respond_to_help_offer`), `cancel` (`cancel_help_offer`). All are `SECURITY DEFINER` RPCs.
- **`VideoShareRepository.shared`** — thin RPC client for in-app video sharing. Calls `share_dream_video(recipient,dream,video,note)`, which creates/reuses a direct chat and inserts a structured `dream_share` message.
- **`ExploreMediaRepository.shared`** — `@MainActor ObservableObject` for Explore/Profile update media. `loadFeed()` ranks dreams with `RankingConfig.explore` and orders the grid by dream rank (recency fallback); `media(ownedBy:)` stays purely chronological for profiles. It fetches videos and photos independently, enriches them with dream/profile context, and maps video rows into `Dream` values for playback/share/detail.
- **`RecommendationRepository.shared`** — thin wrapper over the recommendation RPCs (`get_viewer_ranking_profile`, `get_feed_candidates`) + `supporter_profiles` read/upsert. All scoring happens in the `DreamRanking` package, never here.
- **`FeedQueueService.shared`** — the per-viewer ranked queue: background refill (candidates → pure rank → JSON file in Application Support), cursor-paginated `nextPage(count:)`, `reason(for:)` explainability hook, `reset()` on sign-out.
- **`EngagementLogger.shared`** — buffered engagement-event batcher → `log_engagement_batch` RPC (flush at 10 events / 15 s / app background; unflushed buffer survives kills via UserDefaults).
- **`CommentRepository.shared`** — per-update comment threads (`comments(forDream:videoId:photoId:)`, `post`, `delete`, thread-keyed `counts`). Posting logs a `comment` engagement event.
- **`LikesStore.shared`** (in `LikeRepository.swift`) — the viewer's own likes + live per-card counts, keyed by thread (`Dream.feedID` for clips). `toggle(dreamId:videoId:viewer:currentCount:)` is optimistic and rolls back on failure; `load(forDreams:viewer:)` refreshes both sets. Counts degrade to zero if the likes migrations aren't applied.
- **`DreamDTO.swift`** — `Codable` row types with `snake_case` ⇄ camelCase `CodingKeys`, plus `DreamCategory.dbValue` / `.from(dbValue:)` and `DreamStage` mappings. `DreamVideoDTO` carries `title`, optional `caption`, and `createdAt`; `DreamPhotoUpdateDTO` carries `imagePath`, `title`, optional `caption`, dimensions, and `createdAt`.
- **`MessagingDTO.swift`** — `HelpOfferStatus` enum (mirrors the `help_offer_status` Postgres enum; maps legacy `declined`/`withdrawn` → `rejected`/`cancelled`) + row DTOs (`ConversationDTO`, `ConversationParticipantDTO`, `MessageDTO`, `NotificationDTO`, `HelpOfferRow`), share DTOs (`ShareDreamVideoResult`, `SharedVideoPreview`), and RPC payloads. `MessageDTO.kind` can be `text`, `system`, or `dream_share`; share messages carry `sharedDreamId` / `sharedVideoId`.
- **`AvatarUploader.shared`** — compresses/crops profile images to a square JPEG, uploads to the public `avatars` bucket at `{user_id}/avatar.jpg`, and returns a cache-busted public URL for `profiles.avatar_url`. Uses lowercased user-id paths for storage RLS.
- **`DreamImageUploader.shared`** — fixes image orientation, downscales long edge to ~1800 px, compresses JPEG under the public `dream-images` bucket limit, uploads to `{user_id}/{dream_id}/{image_id}.jpg`, then inserts a `dream_photo_updates` row. Paths must be lowercased for storage RLS.
- **`VideoUploader.shared`** — `upload(localVideoURL:dreamId:markPrimary:title:caption:)` **transcodes via `VideoTranscoder` first** (step 0; falls back to the original on failure), then uploads the video to private `dream-videos`, generates + uploads a poster (JPEG 0.7) to public `dream-posters`, and inserts a `dream_videos` row (metadata probed from the *encoded* file). `markPrimary: false` + a `title` is how a **video update** is posted; the cover video uses `markPrimary: true` and `title: nil`. Also mints signed playback URLs (`signedVideoURL`).
- **`VideoTranscoder`** — plain (non-`@MainActor`) `enum`; `transcode(_:targetBitrate:maxLongEdge:)` re-encodes a local clip via `AVAssetReader`/`AVAssetWriter` to H.264 ~6 Mbps, long-edge ≤1920, AAC 128k, preserving the source's `preferredTransform` (orientation). Has a **skip-guard** (returns the source unchanged if it's already ≤1.2× target bitrate and within the resolution cap). Uses Reader/Writer, **not** `AVAssetExportSession`, because export presets can't set a target bitrate. See Bandwidth & cost below.
- **`VideoExporter` / `VideoActionsModel`** — downloads private videos to local temp files for native system sharing or saving to Photos. Attach via `.videoActions(model)`. This is separate from in-app sharing (`VideoShareRepository`).
- **`FeedVideoPreloader.shared`** — warm-player pool + signed-URL cache **and** the cross-screen feed pause/resume API (`feedActiveID`, `pauseFeedPlayer()`/`resumeFeedPlayer()` with `feedCoverDepth`, `feedMuted`, `.pausesDiscoverFeed()`). See Video playback below.

## Backend (Supabase)

Project ref `ohmtchfldrqobwrtyhmz`. MCP server configured in `.mcp.json` / `.codex/config.toml` (use the `supabase` MCP tools for SQL/migrations/logs/advisors). Schema lives in `supabase/migrations/`:
- `0001_init.sql` — enums, tables, RLS policies, `dream_stats` view, triggers.
- `0002_storage.sql` — storage buckets + storage RLS.
- `0003_harden.sql` — security-advisor hardening.
- `0004_profile_from_metadata.sql` — populate profile handle/name from sign-up metadata.
- `0005_videos_readable_by_all_authed.sql` — relax `dream-videos` SELECT so any authed user can play any video (cross-user feed playback).
- `0006_profile_features.sql` — `follows`, featured dream (`dreams.is_featured`, partial-unique per owner), `profile_stats` view.
- `0007_video_title.sql` — `dream_videos.title` (per-video heading for update clips).
- `0008_help_offer_status.sql` — extends the `help_offer_status` enum (adds `accepted/rejected/in_progress/completed/cancelled`).
- `0009_messaging.sql` — messaging infra: `conversations`, `conversation_participants`, `messages`, `notifications` tables + RLS + Realtime.
- `0010_help_offer_rpc.sql` — `SECURITY DEFINER` RPCs `create_help_offer` / `respond_to_help_offer` / `cancel_help_offer` (+ `mark_conversation_read`, `mark_all_notifications_read`) that drive offers→conversations→notifications atomically.
- `0011_harden_messaging_functions.sql` — locks down `search_path` / permissions on the messaging functions (security-advisor fixes).
- `0012_revoke_anon_messaging_functions.sql` — revokes `anon` EXECUTE on the messaging RPCs (authenticated-only).
- `0013_profile_avatar.sql` — adds `profiles.avatar_url` and avatar delete/read RLS support.
- `0014_avatar_storage_rls.sql` — repair migration for avatar overwrite/remove RLS on already-migrated projects.
- `0015_video_shares.sql` — adds `messages.shared_dream_id` / `shared_video_id`, `dream_share` notifications, and `share_dream_video`.
- `0016_harden_video_share_trigger.sql` — revokes direct RPC execution on trigger-only `on_message_insert()`.
- `0017_search.sql` — full-text search: `fts tsvector` generated columns on `dreams` (English stemmer, title+description) and `profiles` (simple tokeniser, handle+name+location), GIN indexes, `search_dreams(query)` and `search_profiles(query)` RPCs (SECURITY DEFINER, STABLE, authenticated-only). **Must be applied to Supabase Dashboard → SQL Editor before search works.**
- `0018_one_conversation_per_pair.sql` — **one conversation per user pair** (Instagram-style DMs): `get_or_create_direct_conversation(a,b)` helper (advisory-locked, internal-only), rewrites `create_help_offer` + `share_dream_video` to route through it, merges pre-existing duplicate threads (messages/offers/notifications moved to the oldest thread, read receipts merged), and retires `conversations.dream_id` (now always null).
- `0019_security_hardening.sql` — tightens public/authenticated RLS: removes direct `help_offers` updates, limits broad read policies to authenticated users, restricts direct `messages` inserts to plain text only, adds a `profiles` update `WITH CHECK`, and adds private Realtime channel authorization for `conversation:<uuid>`.
- `0020_explore_photo_updates.sql` — adds `dream_videos.caption`, creates `dream_photo_updates` with RLS + explicit authenticated Data API grants, and creates the public `dream-images` storage bucket with owner-only upload/delete policies.
- `0021_help_types.sql` — canonical `help_type` enum (`code/design/funding/mentorship/marketing/legal/space/other`), `to_help_type(text)` normalizer, trigger-synced `dreams.help_types` (derived from free-text `help_tags`, GIN-indexed), and `supporter_profiles` (per-user help types offered, capacity, category interests, stage preferences; own-row RLS).
- `0022_engagement.sql` — `engagement_events` log (view/watch_progress/complete/skip/offer_help/save/share/follow/not_relevant, generated `completion_ratio`), per-viewer `dream_seen` seen-set (TTL'd feed exclusion + dismissal), `dream_exposure_counters` (impressions/distinct_viewers/offers_received; trigger-maintained), and the `log_engagement_batch(jsonb)` ingestion RPC.
- `0023_offer_lifecycle.sql` — connection-funnel instrumentation: `help_offers.accepted_at/completed_at` + `help_offer_events` transition log (offer_sent→accepted→conversation→support_delivered), trigger-driven.
- `0024_feed_candidates.sql` — recommendation read RPCs (SECURITY INVOKER): `get_viewer_ranking_profile()` (capabilities + follows + viewer-local category affinity from own last-30d events) and `get_feed_candidates(limit, seen_ttl_days, underexposed_viewer_floor)` (multi-source CTE union — help-type match, skill overlap, category affinity, geo, followed, fresh, underexposed — with per-dream `sources[]` tags and exposure counters).
- `0025_comments.sql` — `dream_comments` (author-or-owner delete), `dream_comment_counts` view for feed badges, and a `comment` notification to the dream owner (trigger, skips self-comments).
- `0026_per_update_comments.sql` — comment threads become **per-update**: legacy null `video_id` rows backfilled onto the cover clip; `dream_comment_counts` rebuilt per `(dream, video)` with `thread_id = coalesce(video_id, dream_id)` (matches `Dream.feedID`).
- `0027_comments_cascade_with_clip.sql` — deleting a clip cascade-deletes its comment thread (`video_id` FK changed from `set null` to `cascade`).
- `0028_likes.sql` — `dream_likes` (per-clip, `thread_id` generated as `coalesce(video_id, dream_id)`, one like per viewer per thread), `dream_like_counts` view, and a first-like-only owner notification.
- `0029_like_engagement_event.sql` — adds `like` to the engagement event enum.
- `0030_photo_comments.sql` — comment threads become per-**photo** too: `dream_comments.photo_id` (cascade on photo delete), a `video_id is null or photo_id is null` check, and `dream_comment_counts.thread_id` rebuilt as `coalesce(video_id, photo_id, dream_id)`.
- `0031_revoke_public_function_execute.sql` — **anon RPC lockdown.** Postgres grants `EXECUTE` to `PUBLIC` by default, so `grant ... to authenticated` alone never closed anything: `search_dreams` / `search_profiles` are `SECURITY DEFINER` (they bypass RLS) and were callable by `anon`, letting anyone with the shipped publishable key dump the user directory and dream catalog without an account. Revokes those plus the `handle_new_user` / `set_updated_at` trigger functions, and sets `alter default privileges ... revoke execute on functions from public` so new RPCs must opt in.
- `0032_content_integrity_constraints.sql` — **thread integrity + input validation.** Triggers assert a comment's/like's `video_id`/`photo_id` actually belongs to its `dream_id` (otherwise a client could post into someone else's thread while keeping moderation rights, since `thread_id = coalesce(video_id, photo_id, dream_id)` but delete RLS keys on `dream_id`). Adds length/cardinality caps on every user-writable column, a `profiles.handle` format check, and pins `profiles.avatar_url` to our own storage origin (it is self-updatable free text that every viewer's client loads as an image).
- `0033_fk_indexes.sql` — covering indexes for the foreign keys the performance advisor flagged (`notifications.actor_id`, `messages.sender_id`/`shared_*`, `dream_comments.video_id`, `dream_likes.video_id`, …).
- `0034_sanitize_generated_handles.sql` — follow-up to 0032. `handle_new_user()` took the handle straight from sign-up metadata or the email local-part, so 0032's format check made `dream-owner@…`, `user+tag@…`, long addresses and emoji handles **fail account creation outright** (the profile insert runs inside the `auth.users` trigger). Allows `-`, and sanitizes/clamps inside the trigger, falling back to a null handle. Caught by the `comments_test.sql` suite — run the pgTAP suites after any constraint change.

### Tables (all have RLS enabled)
- **`profiles`** (1:1 with `auth.users`, auto-created via `handle_new_user` trigger) — handle, name, avatar_seed, `avatar_url`, location, skills.
- **`dreams`** — owner_id, title, description, `category` (enum), `stage` (enum), location, help_tags[], views_count, `is_featured` (one pinned "main" dream per owner; partial-unique).
- **`journey_steps`** — per-dream timeline (stage, date_label, note, done, sort_order).
- **`dream_videos`** — storage_path, poster_path, duration/width/height, `is_primary` (unique per dream — the cover clip), `title` (per-video heading; null on the cover clip), optional `caption`, created_at. A dream has **many** videos (cover + updates).
- **`dream_photo_updates`** — dream-attached photo updates for Explore/Profile Updates: image_path, title, optional caption, dimensions, created_at. Authenticated users can read; only the owner of the parent dream can write.
- **`follows`** — follower_id / followed_id.
- **`supporters`**, **`help_offers`** — backing + "I can help" offers. `help_offers.status` is the `help_offer_status` enum; rows carry a `conversation_id` link (added in 0008/0009).
- **`conversations`** — **exactly one 1:1 thread per user pair** (`last_message_at`, `last_message_preview`); help offers, video shares and plain texts between the same two people all land in the same thread. `dream_id` is retired (always null since 0018) — dream context lives on `help_offers.dream_id` / `messages.shared_dream_id`.
- **`conversation_participants`** — membership + per-user `last_read_at` (drives read receipts / unread).
- **`messages`** — `conversation_id`, `sender_id`, `body`, `kind` (`text`/`system`/`dream_share`), optional `shared_dream_id` / `shared_video_id`, `created_at`. Client-side direct inserts are only for `kind = 'text'`; `system` and `dream_share` rows are created by RPCs/triggers.
- **`notifications`** — per-user activity feed (`type`, `actor_id`, `dream_id`, `offer_id`, `conversation_id`, `preview`, `read_at`); the source of the tab-bar unread badge.
- **`dream_stats`** (view) — derived supporters_count / offers_count. **`profile_stats`** (view) — videos/followers/following/offers counts.
- **`supporter_profiles`** — what a user can offer (help_types[], weekly capacity, categories_of_interest, preferred_stages); own-row RLS; no UI yet (written via `RecommendationRepository.upsertSupporterProfile`).
- **`engagement_events`** / **`dream_seen`** / **`dream_exposure_counters`** / **`help_offer_events`** — recommendation instrumentation (see "Recommendation system" below). Client writes go ONLY through `log_engagement_batch`.
- **`dream_likes`** — one row per (viewer, card): `thread_id` is a stored generated `coalesce(video_id, dream_id)` with a unique index on `(user_id, thread_id)`, so a like is per **clip**, not per dream (photos currently like against their dream — no `photo_id` column). Insert/delete as self only; the dream owner cannot remove a like. Counts from `dream_like_counts`; the owner is notified on a viewer's *first* like of a dream only.
- **`dream_comments`** — comments with **per-update threads**: each clip (`video_id`) and each photo update (`photo_id`) owns its own comment section and **dies with it** (cascade on clip/photo delete); dreams with no media use a dream-level thread (both null). Thread key = `coalesce(video_id, photo_id, dream_id)` — for a video card that is `Dream.feedID`. A row carries at most one of the two (check constraint). Insert as self only; delete by author or the dream's owner (moderation). Counts from `dream_comment_counts` (one row per thread); the owner gets a `comment` notification. UI: `CommentsSheet` from the feed's comment button and both Explore detail surfaces (`CommentRepository.comments(forDream:videoId:photoId:)`).

DB enum values are short lowercase forms: category `tech/food/art/impact/education/health/music/sport`; stage `idea/early/needs/almost`. **Always map through `DreamCategory.dbValue` / `DreamStage.dbValue`** — never send the human-readable `rawValue`.

### Storage buckets
- **`dream-videos`** — **private** (500 MB limit). Playback only via **signed URLs**.
- **`dream-posters`** — public (5 MB). Thumbnails shown in feed via public URL.
- **`dream-images`** — public (5 MB). Compressed photo updates shown in Explore/Profile via public URL.
- **`avatars`** — public (2 MB).

### ⚠️ Storage RLS path gotcha (important)
Object paths are namespaced by user id as the **first folder**: `{user_id}/{dream_id}/{media_id}.mp4` for videos and `{user_id}/{dream_id}/{media_id}.jpg` for posters/photo updates. Storage RLS checks `(storage.foldername(name))[1] = auth.uid()::text`, and Postgres renders `auth.uid()` **lowercase**. Swift's `UUID.uuidString` is **UPPERCASE**. **All storage paths must be lowercased** (`.uuidString.lowercased()`) or uploads/reads fail with 403/400 RLS violations. See `VideoUploader.upload` and `DreamImageUploader.upload`.

## Video playback system (the feed's perf-critical path)

The feed must start playback instantly while scrolling. Two cooperating types:

- **`DreamVideoBackground`** (Component) — full-bleed per-card background. Shows poster image (or `ScenePoster` gradient fallback), then plays the looping video. Tap to pause/resume. **Pins every layer to the container bounds with a `GeometryReader` + `.frame` + `.clipped()`** — required because `scaledToFill` and `AVPlayerLayer` otherwise report the *media's* natural size for layout (clipping only affects drawing), which inflates the view and shifts the feed's overlay content off-screen. On disappear it only pauses if the disappearing card is **not** the current `FeedVideoPreloader.shared.feedActiveID`; virtual loop duplicates can disappear while the same real video remains active, and pausing there would stop the visible player.

- **`FeedVideoPreloader.shared`** (`@MainActor`) — keeps videos warm so playback starts fast:
  1. **Signed-URL cache** (~1h) so revisiting a card never re-hits the network.
  2. **LRU pool** (max 4) of pre-built, pre-buffered `AVQueuePlayer`s (with `AVPlayerLooper`).
  3. **Faster startup:** `item.preferredForwardBufferDuration = 1`, `automaticallyWaitsToMinimizeStalling = false`, and a `status` KVO observer that calls `preroll(atRate:)` **only once `.readyToPlay`** (calling preroll before ready throws `NSInvalidArgumentException` — don't).
  4. **Coalesced builds** per card (via an in-flight `Task` map) so an early prefetch and the view's own load share one player.
  - `DiscoverScreen` calls `prefetchNeighbors(of:around:)` on first load, on index change, and on feed-count change (warms current + immediate neighbors `[0, 1, -1]` — kept tight on purpose to limit eager neighbor buffering; see Bandwidth & cost).

### ⚠️ Cards are keyed by `feedID`, not dream id (important)
Because one dream can produce several feed cards (cover + updates), all **video-scoped** state must key on **`Dream.feedID`** (`= videoId ?? id`), **not** `dream.id` — otherwise two cards of the same dream collide on one player / signed URL (the wrong clip plays). Discover's endless scroll adds a separate **virtual slot id** (`Int`) for the paged `ScrollView`; that slot id is only for scroll position and must never replace `feedID` for players, signed URLs, saved IDs, expanded descriptions, share payloads, or active feed state. Use `dream.id`/`dream.ownerId` only for navigation (open the dream detail / author profile). Show the card's heading with **`dream.displayTitle`** (`videoTitle ?? title`) and card body with **`dream.displayDescription`** (`videoCaption ?? desc`).

When touching feed/video code, preserve these invariants: **per-video `feedID` keying**, virtual slot ids only for scroll position, bounds-pinning in `DreamVideoBackground`, status-gated preroll, build coalescing, and pause-don't-destroy on disappear.

### Feed pause/resume across covering screens
A screen presented **over** the feed (detail, profile, help sheet, create/update) freezes the presenter, so the feed view can't pause itself. The preloader exposes **`pauseFeedPlayer()` / `resumeFeedPlayer()`**, balanced by an internal **`feedCoverDepth`** counter so the feed only resumes once the **outermost** cover closes (nested covers are safe). `resumeFeedPlayer()` defers a runloop tick (so it lands after the covering view's own `onDisappear`) and restores `feedMuted`.
- `DiscoverScreen` publishes which card is on screen via **`feedActiveID`** (the `feedID`), set in `.task`, on index/feed-count change, **and on `.onAppear`** — the `onAppear` re-mark is required because the feed view now persists inside the paged `TabView` (so `.task` won't re-fire when you page back). On the feed's own `onDisappear` it sets `feedActiveID = nil`.
- Any screen presented over the feed adopts **`.pausesDiscoverFeed()`** (a one-liner modifier in `FeedVideoPreloader.swift` that calls pause on appear / resume on disappear). Applied to `HelpSheet` and the "+" `CreateDreamScreen`/`PostUpdateScreen` covers; `DreamDetailScreen` and the pushed `ProfileScreen` call pause/resume directly in their own `onAppear`/`onDisappear`.
- When a Discover sheet/cover dismisses, call `restoreFeedAfterPresentation` rather than only setting `activeTab`. It recenters the virtual feed and rebuilds the scroll view so the feed never returns half-way between two cards.

## Navigation & gestures

Three cooperating gesture systems sit on top of the feed — when editing any of them, keep the others working:

- **Horizontal tab paging.** `MainShell`'s content is a paged `TabView(selection: $activeTab)`. `DiscoverScreen` uses a vertical paged `ScrollView` with `.scrollTargetBehavior(.paging)` inside that horizontal `TabView`; keep the axes separate so vertical feed paging does not steal horizontal tab swipes. Do not add broad gestures or global hit-testing overlays to Discover without re-checking horizontal tab swipes.
- **Tab bar collapse.** `DreamTabBar` takes a `collapsed: Binding<Bool>`; when true it scales down (`scaleEffect(... anchor: .bottom)`) and dims. `DiscoverScreen` sets `tabBarCollapsed = true` on a vertical feed swipe; any tap on the bar (a tab **or** "+") sets it back to false, and `MainShell` resets it on `activeTab` change. **All** collapse/expand transitions route through a single `.animation(.smooth(...), value: collapsed)` modifier — set `collapsed` *outside* `withAnimation` so taps animate with the same smooth curve (don't wrap it in a separate spring). **Scale must wrap the fully-assembled pill** (after `.background`/`.clipShape`/`.shadow`), not the inner `HStack`, or only the icons shrink and the capsule background stays full size.
- **Tab bar hide in chat.** `MainShell` holds `@State private var tabBarHidden = false` and passes it to `ActivityScreen` as `@Binding var isTabBarHidden`. When `navPath` in `ActivityScreen` becomes non-empty (chat or dream detail is pushed), `isTabBarHidden = true` and the `DreamTabBar` slides off-screen (`.offset(y: 150)`). When navPath empties again (user goes back), `isTabBarHidden = false` and the bar slides back.
- **Tab bar hide during Explore search.** `MainShell` also holds `exploreSearchFocused` and passes it into `ExploreScreen`. The tab bar uses `shouldHideTabBar = tabBarHidden || exploreSearchFocused`, so focusing the Explore search field hides the floating capsule instead of letting the keyboard lift it over the UI. Clear the focus binding when leaving Explore.
- **Keyboard-safe chat composer.** `RootView` ignores only `.container` on the bottom, while `DreamTabBar` independently ignores `.keyboard` so it stays at the physical bottom in search. `ChatScreen` puts its composer in `.safeAreaInset(edge: .bottom)` rather than as the last child of the main `VStack`; this keeps the message field above the keyboard. The first chat history render uses `.defaultScrollAnchor(.bottom)`, hides the list until `ChatRepository.isLoading` finishes, performs non-animated bottom jumps, then reveals it so entering a chat never visibly scrolls or "hovers" upward.
- **Sheet `onDismiss` tab/feed restore.** SwiftUI's paged `TabView` can jump one tab left when a `.sheet` or `.fullScreenCover` is dismissed from inside a tab (known SwiftUI bug), and Discover's virtual feed can restore between slots. Fix: every sheet/cover in `DiscoverScreen` uses `restoreFeedAfterPresentation`, which sets `activeTab.wrappedValue = .discover`, recenters the current virtual slot, and resets `feedResetToken`. **Do not remove this pattern** when adding new sheets to `DiscoverScreen`.
- **Snap-back when tabBarHidden.** If the user accidentally swipes to a different tab while `tabBarHidden == true` (they're inside a chat or dream detail), `MainShell.onChange(of: activeTab)` snaps them back to `.activity` via `DispatchQueue.main.async`. This prevents getting stranded on Explore with no visible tab bar.
- **Edge-swipe back.** Covers have no native interactive dismiss, so `.interactiveBackSwipe(slideOff:_:)` (in `InteractiveBackSwipe.swift`) adds a left-edge strip that tracks a rightward drag and dismisses past a distance/velocity threshold. The strip is inset top/bottom so it never swallows a top-left back button or bottom CTA, and is narrow (24pt) so it doesn't block interior vertical scrolling. `slideOff: true` (default) now caps visible drag to a small amount and commits `onBack` during the drag once the threshold is crossed; it must **not** slide the whole screen off first, because that exposes SwiftUI's blank presentation host as a white flash. **`slideOff: false`** springs back in place and is for **popping a step within a still-mounted screen**.
  - `ChatScreen` can run inside `ActivityScreen`'s `NavigationStack`, so Activity passes an explicit `onBack` that removes the last `navPath` entry. Avoid combining `dismiss()` with `navPath.removeLast()` for the same swipe; that can produce delayed/default navigation animation.
  - **Multi-step sheets own their back logic.** `HelpSheet` ("I can help" / "Offer your help") is a multi-step flow driven by an internal `mode` (`.pick` → `.configure`). Its back-swipe lives **inside** the sheet (`.interactiveBackSwipe(slideOff: false) { goBack() }`) so it **steps back to `.pick` before closing** the sheet, mirroring the in-flow "Back" button — not bolted on at the presentation site (which would always dismiss the whole sheet). When a presented screen has its own internal navigation, give it `slideOff: false` and let it decide pop-vs-dismiss.

## Messaging & Activity (Realtime)

The "I can help" action creates a **help offer** which posts into the pair's **1:1 conversation** and raises **notifications**, all via `SECURITY DEFINER` RPCs (so the workflow is atomic and RLS-safe). The Discover **Send** action opens `InAppShareSheet`, which lists `ProfileRepository.followingProfiles()` and calls `share_dream_video` through `VideoShareRepository`; that RPC inserts a `dream_share` message and relies on the normal message trigger to notify the recipient. **There is exactly one conversation per user pair** (since migration 0018): both RPCs resolve it via `get_or_create_direct_conversation(a,b)`, so offers, shares and texts between the same two people always share one thread — never create conversations directly from Swift or a new RPC without going through that helper. Two repos own the live surface:

- **`ActivityRepository.shared`** (app-wide singleton) aggregates notifications + conversations + offers and keeps `unreadCount` live over one `activity:{userId}` channel subscribed to the user's `notifications` (INSERT + UPDATE). Its `load()` is an intentionally batched 3-phase fan-out (`async let`) that resolves ids → rows → referenced profiles/dreams. **Keep the channel alive even when the user leaves the Activity tab** — the tab-bar badge depends on it.
- **`ChatRepository`** (one per `ChatScreen`) owns a private `conversation:{conversationId}` channel with **four** streams: message INSERTs, `conversation_participants` UPDATEs (read receipts), a `typing` **broadcast**, and **presence**. It also hydrates `dream_share` messages into `SharedVideoPreview` cards by fetching referenced dreams/videos. It `track`s its own presence on subscribe and **must `stop()` on screen disappear** (`ChatScreen.onDisappear`) to tear the channel down.
- **Activity is messages-first.** `ActivityScreen.Section` order is `Messages → Activity → Offers`, and the default selected section is `.messages`. Keep messages as the primary surface; Activity/Offers remain available as pills and retain badges where relevant.

**In-app sharing conventions:**
- Use `VideoShareRepository.share(dream:recipientId:note:)` for sending a feed video to another user inside Dream. Do not insert share rows directly from Swift.
- Shares land in the pair's single 1:1 thread (same thread as help-offer chatter), resolved server-side by `get_or_create_direct_conversation`.
- Shared video messages use `kind = 'dream_share'` plus `shared_dream_id` and `shared_video_id`; keep `MessageBubble` rendering distinct from plain text/system messages.
- Native export/share (`VideoExporter`, `VideoActionsModel`, `ShareSheet`) is only for outside-the-app system sharing or saving to Photos.

**Realtime cost conventions (don't regress these):**
- **Debounce realtime-driven reloads.** A burst of notification events must coalesce into **one** `ActivityRepository.load()` (it uses a ~400 ms `scheduleReload`), not one reload per event.
- **Debounce read receipts.** Incoming chat messages schedule a single `mark_conversation_read` RPC (~1 s `scheduleMarkRead`), not one RPC per message.
- **Throttle typing** broadcasts (~3 s between sends).
- **Optimistic local updates** where possible (e.g. `markAllRead` flips local state instead of a full reload).

## Bandwidth & cost (Supabase egress/storage)

Video is ~99% of the byte cost, so the rules here matter:

- **Always transcode before upload.** `VideoUploader.upload` runs `VideoTranscoder` first (target ~6 Mbps H.264, ≤1080p). Camera captures are ~15 Mbps full-HD — ~2.5× larger for no visible gain in a phone-sized vertical feed. Transcoding cuts stored size **and** every byte of playback egress ~60%. Don't add an upload path that bypasses it.
- **Keep prefetch tight** (`[0, 1, -1]`) — each prefetched card eagerly buffers ~1 s of video.
- **Queries:** prefer explicit column `select(...)` over bare `select()`, and add `.limit(...)` to single-entity fetches (`dreams(ownedBy:)`, `videos(forDream:)`). ⚠️ **Do not** put a blanket `.limit()` on the `.in(...)` fan-out queries in `DreamRepository.fetchContext` — one limit caps *total* rows across all dreams and silently drops feed cards.
- **Poster loading:** use `PosterImage` for poster URLs so thumbnails share the in-memory cache and avoid duplicate network/image decode work.

## Recommendation system (feed ranking)

Two-sided matching, NOT an engagement feed: the success metric is successful connections (help offers → conversations → delivered support). Full tuning guide: `docs/RANKING_TUNING.md`.

- **Pure ranker:** local Swift package `Packages/DreamRanking` (zero deps; `cd Packages/DreamRanking && swift test`). `DreamRanker.rank(candidates:viewer:config:now:seed:)` runs fairness pass → scoring → diversity assembly → reasons. Every weight lives in `RankingConfig`, which has two presets: `.default` (Discover — capability-matching-first, 14-day seen-TTL) and `.explore` (Explore — recency + interest-first, help-type still present, `seenTTLDays = 0` so only dismissals hide; fairness/diversity identical in both). `swift run ranking-demo <candidates.json> <profile.json>` prints a ranked feed from RPC output.
- **Split of labor:** SQL (`get_feed_candidates`) generates ~300 multi-source candidates with exposure counters; ALL scoring happens on-device in the package. Add new candidate sources (e.g. embeddings) as another CTE in the RPC + a `CandidateSource` case — nothing else changes.
- **App wiring (LIVE):** `FeatureFlags.rankedFeedEnabled` = true routes `DreamRepository.loadFeed()` → `loadRankedFeed()` → `FeedQueueService` (device-local ranked queue, refills below 20) → existing enrich pipeline, with a chronological fallback when the queue is empty. Ranked Discover cards are **seen-aware**: first encounter shows the dream's cover clip, a previously-seen dream (any `dream_seen` row) shows its newest clip instead. `EngagementLogger` batches events to `log_engagement_batch` (flush at 10 events / 15 s / background). DiscoverScreen logs: `view` once per dream per session (the virtual loop must NOT inflate impressions), watch-time on card change (< 3 s → `skip`, ≥ clip length → `complete`, else `watch_progress`), `save`/`follow`/`share`/`offer_help`/`comment` at their action sites, and `not_relevant` from the More menu ("Not interested" — hides the dream locally + dismisses server-side). Supporter capabilities ("How You Can Help" + "Interests") are captured in `EditProfileScreen` → `supporter_profiles`.
- **Explore is ranked too:** `ExploreMediaRepository.loadFeed()` ranks dreams with `RankingConfig.explore`, orders grid items by dream rank (each dream's media newest-first, unranked leftovers incl. own dreams trailing by recency), pulls media for top-ranked dreams even when their clips are older than the recent window, filters dismissed dreams, and falls back to the recency grid on failure. The full-screen viewer (`ExploreMediaDetailSheet`) logs one `view` per dream per presentation; grid thumbnails never log. `ProfileScreen`'s `media(ownedBy:)` path is untouched.
- **Invariants (do not break):** (1) fairness slots (positions 2 & 7 per page) are filled by exposure deficit BEFORE scoring; (2) watch/skip signals shape only the watching viewer's own affinity — `DreamCandidate` deliberately carries no aggregate watch field, and `dream_seen` is one row per (user, dream) so repeat skips can't move global counters; (3) production quality (`hasVideo`) is never a ranking input.
- **Seed/inspection:** `supabase/seed.sql` is **local-only** (writes `auth.users`; guarded). `supabase/queries/fairness_report.sql` reports exposure/offers per dream, zero-offer share after 30 d, and the offer funnel. `supabase/tests/ranking_test.sql` is the transactional pgTAP suite (safe on hosted — rolls back).

## Conventions

- **Design system.** The app's design system is a SwiftUI port of the Claude Design project *Dream Design System* (`c3683766-0437-4105-8f1a-765ee8e2c8c8`). That project is the source of truth: if a token or component changes there, port it here — `tokens/*.css` → `Theme/DreamTokens.swift`, `components/**` → `Components/`.
- **Colors:** always a semantic role from `DreamTheme` — `Surface.page/card/sunken/warm`, `Text.primary/secondary/tertiary`, `Border.standard/strong`, `Accent.base/deep/soft/tint`, `Status.*`. The older flat names (`DreamTheme.ink`, `.blue`, `.line`, `.bg`, `.paper`) are aliases onto those roles and are fine to keep using. Never hardcode `Color(red:…)`; use `Color(hex:)` only when defining a token.
- **Dark mode is on.** Every `DreamTheme` color is a *dynamic* color built with `Color(light:dark:)`, so it resolves against the current trait collection and call sites never branch on scheme. Two consequences:
  - Never use bare `.primary`/`.secondary`/`.white` for anything that sits on a page surface. A white fill does not invert, so light text lands on it in dark mode. Use `Surface.card` for the fill.
  - Chrome that sits **over video** is deliberately mode-invariant: use `Glass.fill/fillStrong/stroke` and `OnMedia.base/dim`. If you put fixed-color text on a fixed-color chip over media, fix *both* colors — pairing `OnMedia.base` with `Text.primary` inverts one half of the pair.
- **Spacing/radii/elevation/motion:** `DreamSpace` (18-step scale + `screenGutter`/`safeTop`/`safeBottom`), `DreamRadius`/`DreamShape` (squircles — always `.continuous`; prefer `DreamShape.sm/md/lg/xl` so the style can't be dropped), `DreamShadow` (four roles only — the system uses hairline borders, and shadows are reserved for things that float), `DreamMotion`. Don't introduce magic numbers.
- **Typography:** roles, not point sizes — `.dreamStyle(.display(_)/.title(_)/.body(_)/.ui(_)/.label)`, which carry tracking, line spacing and Dynamic Type anchoring. The two faces are Instrument Sans (everything, including headlines) and Instrument Serif (**italic accent words only**, never paragraphs). The signature headline is sans-bold with one serif-italic accent word — use `DreamHeadline("What's", accent: "happening")`. `DreamTheme.Font.display/text` are deprecated shims kept for un-migrated call sites.
- **Fonts are registered at runtime** by `DreamFonts.register()` from `DreamApp.init()`, because `UIAppFonts` can't be expressed as an `INFOPLIST_KEY_*` build setting and the target generates its Info.plist. Drop a new `.ttf` in `Resources/Fonts` and add its PostScript name to `DreamFontFace`.
- **Categories:** drive UI color from `dream.category.palette` (fg/bg/tint).
- **Reusable UI:** before writing another local copy of a treatment, check `Components/` — `DreamButton` (+`DreamPressStyle`), `DreamTextField`/`SearchField`, `DreamSurface`/`DreamNote`, `DreamSheet`, `PageHeader`, `SegmentedControl`, `ChipSelect`/`DreamChip`, `EmptyState`, `Skeleton`, `Toast`, `OptionRow`, `IconButton`, `EngagementBar`, `CategoryBadge`, `StagePill`, `FollowButton`, `StatCell`/`StatRow`, `EyebrowLabel`, `Avatar`, `ThreeColumnGrid`, `PosterImage`.
- **Component gallery:** `DesignSystemGallery` (debug only) renders every component on one page in the current scheme. Flip `ContentView.showsDesignGallery`, or screenshot a section directly with `--gallery-section=<Section>`. `--initial-tab=<explore|activity|profile>` opens a tab, since the simulator can't be scripted to tap the tab bar.
- **Concurrency:** services/repos that touch UI state are `@MainActor`. Use `async let` for independent Supabase fetches (see `loadFeed`).
- **Singletons:** `*.shared` for services; inject nothing — call directly.
- **Compose UI:** the new-dream and update flows (`CreateDreamScreen`, `PostUpdateScreen`) share their source cards, video/photo previews, thumbnail loader and video picker wrapper via `Components/VideoCompose.swift`. Photo pickers live in `VideoPicker.swift`; image upload lives in `DreamImageUploader`. Reuse those rather than re-implementing — only each screen's unique fields (full dream form vs. update title/caption) live in the screen.
- **Engagement icons:** the heart means **like** and nothing else. "I can help" uses `hands.sparkles` (`EngagementBar.Item.help`, `DreamButton(icon: "hands.sparkles")`) — two hearts on one rail read as the same action.
- **Discover author row:** show the creator avatar beside `@handle`; the Follow/Following button sits immediately to the right of the handle and should match the compact squircle treatment of the category/stage tags (`FollowButton(style: .feed)`).
- **Tab bar:** the bottom nav is the floating `DreamTabBar` squircle, overlaid by `MainShell` (it does **not** push content up). New tabs go through it + a new `TabView` page/tag in `MainShell.tabContent`. Any screen presented over the feed should pause the feed video (`.pausesDiscoverFeed()` or direct pause/resume) and, if dismissable, use `.interactiveBackSwipe`.
- **Auth note:** `RootView` gates the onboarding screen on `AuthService.isSignedIn` (the real Supabase session). Auth is **email + password** (`AuthScreen` → `AuthService.signIn`/`signUp`); `restoreSession()` runs at launch to restore a persisted session. Sign-up may land in `awaitingEmailConfirmation` if the project requires email confirmation (no session returned).

## Git

`origin` is a single remote — `git@github.com:dreambydreamers/Dream.git` — used for both fetch and push. `git push origin` and `git pull` go there and nowhere else.

Main branch: `main`. Active feature branch: `design-system-upgrade`.
