# AGENTS.md

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
DreamApp (@main)                (.preferredColorScheme(.light) — app is light-only)
└─ ContentView → RootView
   ├─ OnboardingScreen          (shown until AuthService.isSignedIn; AuthScreen = email/password)
   └─ MainShell                 → paged TabView (swipeable) + floating DreamTabBar overlay
      ├─ DiscoverScreen         (the video feed — the heart of the app)
      ├─ ExploreScreen          (Instagram-style grid of mock posts + Supabase full-text search)
      ├─ ActivityScreen         (notifications + conversations + help offers, live over Realtime)
      │   ├─ ChatScreen         (1:1 live chat — typing, presence, read receipts, video shares)
      │   └─ DreamDetailFromIdView  (dream detail opened by tapping a shared video in chat)
      ├─ ProfileScreen          (current user or any author; 3 tabs: Dreams / Updates / Saved)
      └─ "+" → CreateDreamScreen (new dream)  ·  PostUpdateScreen (update clip)
```

`MainShell` lays out the four tab screens in a **horizontally-paged `TabView`** (`.tabViewStyle(.page(indexDisplayMode: .never))`, selection bound to `activeTab`), with the floating `DreamTabBar` overlaid at the bottom of a `ZStack`. So tabs are reachable **both** by tapping the bar and by **swiping left/right** between adjacent tabs (order: Discover → Explore → Activity → Profile). See **Navigation & gestures** below.

The **"+" tab button** routes based on whether the user already has a dream (`DreamRepository.myDream()`): no dream → `CreateDreamScreen`; has a dream → a confirmation dialog offering **"Post an update"** (`PostUpdateScreen`) or **"Start a new dream"** (`CreateDreamScreen`). The same `PostUpdateScreen` is also reachable from the "Post an update" button on the owner's `ProfileScreen`. "+" is an **action, not a page** — it is not a TabView tag, just a button in the bar.

### Directory layout (`Dream/`)
- **`DreamApp.swift`** — entry point; applies **`.preferredColorScheme(.light)`** (the app is light-only — see Conventions) and calls `AuthService.shared.restoreSession()` on launch.
- **`RootView.swift`** — top-level routing + `MainShell` tab container + "+" routing + publish/update toast. `MainShell` holds `ActivityRepository.shared` so the tab-bar unread badge stays live even off the Activity tab.
- **`Models/Dream.swift`** — `Dream`, `JourneyStep` view models; `DreamStage` enum. `Dream` is one *video card* (see `feedID`, `displayTitle`, `videoId`, `videoTitle`).
- **`Theme/DreamTheme.swift`** — all colors, fonts, `DreamCategory` + per-category palettes, `Color(hex:)`. **All theme colors are fixed (non-adaptive) light-mode values.**
- **`Screens/`** — full screens (Discover, CreateDream, **PostUpdate**, DreamDetail, HelpSheet, Profile, EditProfile, Auth, Onboarding, **Activity**, **Chat**, placeholders).
- **`Components/`** — reusable views (ActionButton, Avatar, CategoryBadge, **DreamAchievements**, **DreamTabBar**, DreamVideoBackground, **EyebrowLabel**, FlowLayout, **FollowButton**, **GlassCircleButton**, **InAppShareSheet**, **InteractiveBackSwipe**, JourneyTimeline, MediaVideoPlayer, **PosterImage**, PrimaryButton, ScenePoster, **ShareSheet**, **StatCell**, **ThreeColumnGrid**, VideoPicker, **VideoCompose**). `VideoCompose.swift` holds the shared compose pieces (`loadVideoThumbnail`, `VideoSourceCard`, `VideoPreviewCard`, `.videoSourcePicker(...)`) used by **both** CreateDream and PostUpdate — keep new compose UI here rather than duplicating it. `PosterImage` is the shared cached remote-poster loader; use it for feed/share/detail/profile thumbnails instead of ad hoc `AsyncImage`. `FollowButton`, `GlassCircleButton`, `StatCell`, `EyebrowLabel`, and `ThreeColumnGrid` centralize repeated UI treatments. `InAppShareSheet` is the Instagram-style send-to-friend sheet for sharing feed videos into direct chats. `DreamTabBar` is a **floating translucent capsule** (icon-only, animated active highlight via `matchedGeometryEffect`, blue accent "+", optional unread `badge`); `InteractiveBackSwipe.swift` holds the `.interactiveBackSwipe(...)` / `ConditionalBackSwipe` edge-swipe-back modifiers — see **Navigation & gestures**.
- **`Services/`** — Supabase client, repos (`DreamRepository`, `ProfileRepository`, `ActivityRepository`, `ChatRepository`, `HelpOfferRepository`, `VideoShareRepository`), DTOs (`DreamDTO`, `MessagingDTO`), uploaders/exporters (`AvatarUploader`, `VideoUploader`, `VideoTranscoder`, `VideoExporter`), auth, video preloader.
- **`Config/SupabaseConfig.swift`** — Supabase URL + publishable (anon) key. Safe to ship; security is enforced by RLS.

### Discover screen features (`DiscoverScreen.swift`)
Beyond the core video feed:
- **Endless vertical paging**: the feed uses SwiftUI's paged vertical `ScrollView` with repeated **virtual slots** (`currentSlot: Int?`, `feedCycleCount`, `feedResetToken`) so scrolling past the last video continues back to the first. The virtual slot is only a scroll identity; real video state still keys on `dream.feedID`.
- **Loop normalization**: when the user reaches an edge copy of the virtual feed, `normalizeLoopSlotIfNeeded()` silently snaps back to the middle copy of the same real video with animations disabled. Do not replace this with real duplicated dreams or duplicate player/cache keys.
- **Presentation restore**: every Discover sheet/cover (`DreamDetailScreen`, `HelpSheet`, `InAppShareSheet`, pushed `ProfileScreen`) uses `restoreFeedAfterPresentation`. It restores `activeTab = .discover`, recenters the current video on its middle virtual slot, and changes `feedResetToken` to rebuild the paged scroll view. This prevents the "two videos visible" bug after dismissing the share sheet.
- **Inactive virtual cards are visual-only**: card chrome (title, author row, buttons, gradients) renders only for the centered active slot. Neighboring virtual copies may be partly visible during paging/restore, but must not show duplicate controls.
- **Bookmark (Save)**: bookmark icon saves/unsaves the current dream to `SavedDreamsStore`. Filled icon = saved. Haptic feedback on toggle.
- **Three-dots menu**: `confirmationDialog` with "Save to Gallery" (system photo export) and "Share outside Dream" (native share sheet) via `VideoActionsModel`.
- **Expandable description**: description text truncates at 2 lines with a tappable "more" label that expands to full text. State keyed on `feedID` via `expandedDesc: Set<UUID>`.

### Services
- **`SupabaseService.shared.client`** — the single `SupabaseClient`. Always go through this.
- **`AuthService.shared`** — `@MainActor ObservableObject`. **Email + password** auth (`signIn`/`signUp`/`signOut`); `restoreSession()` on launch restores any persisted session. Subscribes to `auth.authStateChanges` and exposes `userId`, `isSignedIn`, `isBusy`, `errorMessage`, and `awaitingEmailConfirmation` (set when sign-up succeeds but the project requires email confirmation, so no session is returned). `AuthScreen` drives this.
- **`DreamRepository.shared`** — `@MainActor ObservableObject`, `@Published dreams`. A shared `fetchContext(_:)` loads profiles + stats + **all** videos + journey steps **concurrently** (`async let`), then two mappers consume it:
  - `loadFeed()` → `enrichFeed(...)` emits **one card per video** (cover + updates), interleaved across dreams by the video's `created_at` desc; dreams with no video still emit one (gradient) card.
  - `dreams(ownedBy:)` → `enrich(...)` emits **one card per dream** using its primary video (used by the profile).
  - Also: `createDream(...)`, `myDream()` (the user's featured-or-latest dream, the update target), `setFeatured(...)`, `videos(forDream:)` → `[DreamMedia]`.
- **`ProfileRepository.shared`** — `@MainActor ObservableObject` for profile fetch, batch `profiles(ids:)`, `stats` (`profile_stats` view), profile edit, avatar URL update, follow/unfollow, and `followingProfiles()` for in-app share recipients. It publishes `lastError` for user-visible failures.
- **`ActivityRepository.shared`** — `@MainActor ObservableObject`, **app-wide singleton** (`start()` once signed in; keep it alive — the tab-bar badge depends on it, do **not** `stop()` on tab leave). Aggregates `notifications` + `conversations` + `offersMade`/`offersReceived`, publishes `lastError`, and keeps a live `unreadCount` via a `notifications` Realtime channel. See Messaging & Activity below.
- **`ChatRepository`** — **one instance per open `ChatScreen`** (`start()` on appear, `stop()` on disappear). Drives a single conversation: bounded newest-first history fetch, send, share-preview hydration for `dream_share` messages, and a private `conversation:{id}` Realtime channel (`isPrivate = true`) for message inserts, read-receipt updates, typing broadcast, and presence. See Messaging & Activity below.
- **`HelpOfferRepository.shared`** — thin RPC client for the help-offer workflow: `createOffer` (`create_help_offer`), `respond` (`respond_to_help_offer`), `cancel` (`cancel_help_offer`). All are `SECURITY DEFINER` RPCs.
- **`VideoShareRepository.shared`** — thin RPC client for in-app video sharing. Calls `share_dream_video(recipient,dream,video,note)`, which creates/reuses a direct chat and inserts a structured `dream_share` message.
- **`DreamDTO.swift`** — `Codable` row types with `snake_case` ⇄ camelCase `CodingKeys`, plus `DreamCategory.dbValue` / `.from(dbValue:)` and `DreamStage` mappings. `DreamVideoDTO` carries `title` (per-video heading) and `createdAt`.
- **`MessagingDTO.swift`** — `HelpOfferStatus` enum (mirrors the `help_offer_status` Postgres enum; maps legacy `declined`/`withdrawn` → `rejected`/`cancelled`) + row DTOs (`ConversationDTO`, `ConversationParticipantDTO`, `MessageDTO`, `NotificationDTO`, `HelpOfferRow`), share DTOs (`ShareDreamVideoResult`, `SharedVideoPreview`), and RPC payloads. `MessageDTO.kind` can be `text`, `system`, or `dream_share`; share messages carry `sharedDreamId` / `sharedVideoId`.
- **`AvatarUploader.shared`** — compresses/crops profile images to a square JPEG, uploads to the public `avatars` bucket at `{user_id}/avatar.jpg`, and returns a cache-busted public URL for `profiles.avatar_url`. Uses lowercased user-id paths for storage RLS.
- **`VideoUploader.shared`** — `upload(localVideoURL:dreamId:markPrimary:title:)` **transcodes via `VideoTranscoder` first** (step 0; falls back to the original on failure), then uploads the video to private `dream-videos`, generates + uploads a poster (JPEG 0.7) to public `dream-posters`, and inserts a `dream_videos` row (metadata probed from the *encoded* file). `markPrimary: false` + a `title` is how an **update clip** is posted; the cover video uses `markPrimary: true` and `title: nil`. Also mints signed playback URLs (`signedVideoURL`).
- **`VideoTranscoder`** — plain (non-`@MainActor`) `enum`; `transcode(_:targetBitrate:maxLongEdge:)` re-encodes a local clip via `AVAssetReader`/`AVAssetWriter` to H.264 ~6 Mbps, long-edge ≤1920, AAC 128k, preserving the source's `preferredTransform` (orientation). Has a **skip-guard** (returns the source unchanged if it's already ≤1.2× target bitrate and within the resolution cap). Uses Reader/Writer, **not** `AVAssetExportSession`, because export presets can't set a target bitrate. See Bandwidth & cost below.
- **`VideoExporter` / `VideoActionsModel`** — downloads private videos to local temp files for native system sharing or saving to Photos. Attach via `.videoActions(model)`. This is separate from in-app sharing (`VideoShareRepository`).
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

### Tables (all have RLS enabled)
- **`profiles`** (1:1 with `auth.users`, auto-created via `handle_new_user` trigger) — handle, name, avatar_seed, `avatar_url`, location, skills.
- **`dreams`** — owner_id, title, description, `category` (enum), `stage` (enum), location, help_tags[], views_count, `is_featured` (one pinned "main" dream per owner; partial-unique).
- **`journey_steps`** — per-dream timeline (stage, date_label, note, done, sort_order).
- **`dream_videos`** — storage_path, poster_path, duration/width/height, `is_primary` (unique per dream — the cover clip), `title` (per-video heading; null on the cover clip), created_at. A dream has **many** videos (cover + updates).
- **`follows`** — follower_id / followed_id.
- **`supporters`**, **`help_offers`** — backing + "I can help" offers. `help_offers.status` is the `help_offer_status` enum; rows carry a `conversation_id` link (added in 0008/0009).
- **`conversations`** — **exactly one 1:1 thread per user pair** (`last_message_at`, `last_message_preview`); help offers, video shares and plain texts between the same two people all land in the same thread. `dream_id` is retired (always null since 0018) — dream context lives on `help_offers.dream_id` / `messages.shared_dream_id`.
- **`conversation_participants`** — membership + per-user `last_read_at` (drives read receipts / unread).
- **`messages`** — `conversation_id`, `sender_id`, `body`, `kind` (`text`/`system`/`dream_share`), optional `shared_dream_id` / `shared_video_id`, `created_at`. Client-side direct inserts are only for `kind = 'text'`; `system` and `dream_share` rows are created by RPCs/triggers.
- **`notifications`** — per-user activity feed (`type`, `actor_id`, `dream_id`, `offer_id`, `conversation_id`, `preview`, `read_at`); the source of the tab-bar unread badge.
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

- **`DreamVideoBackground`** (Component) — full-bleed per-card background. Shows poster image (or `ScenePoster` gradient fallback), then plays the looping video. Tap to pause/resume. **Pins every layer to the container bounds with a `GeometryReader` + `.frame` + `.clipped()`** — required because `scaledToFill` and `AVPlayerLayer` otherwise report the *media's* natural size for layout (clipping only affects drawing), which inflates the view and shifts the feed's overlay content off-screen. On disappear it only pauses if the disappearing card is **not** the current `FeedVideoPreloader.shared.feedActiveID`; virtual loop duplicates can disappear while the same real video remains active, and pausing there would stop the visible player.

- **`FeedVideoPreloader.shared`** (`@MainActor`) — keeps videos warm so playback starts fast:
  1. **Signed-URL cache** (~1h) so revisiting a card never re-hits the network.
  2. **LRU pool** (max 4) of pre-built, pre-buffered `AVQueuePlayer`s (with `AVPlayerLooper`).
  3. **Faster startup:** `item.preferredForwardBufferDuration = 1`, `automaticallyWaitsToMinimizeStalling = false`, and a `status` KVO observer that calls `preroll(atRate:)` **only once `.readyToPlay`** (calling preroll before ready throws `NSInvalidArgumentException` — don't).
  4. **Coalesced builds** per card (via an in-flight `Task` map) so an early prefetch and the view's own load share one player.
  - `DiscoverScreen` calls `prefetchNeighbors(of:around:)` on first load, on index change, and on feed-count change (warms current + immediate neighbors `[0, 1, -1]` — kept tight on purpose to limit eager neighbor buffering; see Bandwidth & cost).

### ⚠️ Cards are keyed by `feedID`, not dream id (important)
Because one dream can produce several feed cards (cover + updates), all **video-scoped** state must key on **`Dream.feedID`** (`= videoId ?? id`), **not** `dream.id` — otherwise two cards of the same dream collide on one player / signed URL (the wrong clip plays). Discover's endless scroll adds a separate **virtual slot id** (`Int`) for the paged `ScrollView`; that slot id is only for scroll position and must never replace `feedID` for players, signed URLs, saved IDs, expanded descriptions, share payloads, or active feed state. Use `dream.id`/`dream.ownerId` only for navigation (open the dream detail / author profile). Show the card's heading with **`dream.displayTitle`** (`videoTitle ?? title`).

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

## Conventions

- **Colors/fonts:** always use `DreamTheme` (`DreamTheme.blue`, `DreamTheme.Font.display/text`, `Color(hex:)`). Don't hardcode `Color(red:…)`.
- **Light-mode only.** Every `DreamTheme` color is a fixed light value and `DreamApp` pins `.preferredColorScheme(.light)`. **Never rely on adaptive system colors** — a `TextField`/`Text` with no explicit color falls back to `.primary`, which turns white in a device's dark mode and vanishes on the app's light backgrounds. Always set an explicit text color on inputs (`DreamTheme.ink` / `Color.black`).
- **Categories:** drive UI color from `dream.category.palette` (fg/bg/tint).
- **Reusable UI:** prefer `FollowButton`, `GlassCircleButton`, `StatCell`, `EyebrowLabel`, `ThreeColumnGrid`, and `PosterImage` before creating another local copy of the same treatment.
- **Concurrency:** services/repos that touch UI state are `@MainActor`. Use `async let` for independent Supabase fetches (see `loadFeed`).
- **Singletons:** `*.shared` for services; inject nothing — call directly.
- **Compose UI:** the new-dream and update flows (`CreateDreamScreen`, `PostUpdateScreen`) share their source cards, preview, thumbnail and pickers via `Components/VideoCompose.swift`. Reuse those rather than re-implementing — only each screen's unique fields (full dream form vs. a single heading) live in the screen.
- **Discover author row:** show the creator avatar beside `@handle`; the Follow/Following button sits immediately to the right of the handle and should match the compact translucent capsule treatment of the category/stage tags.
- **Tab bar:** the bottom nav is the floating `DreamTabBar` capsule, overlaid by `MainShell` (it does **not** push content up). New tabs go through it + a new `TabView` page/tag in `MainShell.tabContent`. Any screen presented over the feed should pause the feed video (`.pausesDiscoverFeed()` or direct pause/resume) and, if dismissable, use `.interactiveBackSwipe`.
- **Auth note:** `RootView` gates the onboarding screen on `AuthService.isSignedIn` (the real Supabase session). Auth is **email + password** (`AuthScreen` → `AuthService.signIn`/`signUp`); `restoreSession()` runs at launch to restore a persisted session. Sign-up may land in `awaitingEmailConfirmation` if the project requires email confirmation (no session returned).

## Git

`origin` is a single remote — `git@github.com:dreambydreamers/Dream.git` — used for both fetch and push. `git push origin` and `git pull` go there and nowhere else.

Main branch: `main`. Active feature branch: `activity`.
