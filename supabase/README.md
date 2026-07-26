# Dream Supabase Backend

This directory holds the SQL schema, RLS policies, storage setup, Realtime config, and RPC workflows for the Dream Supabase project.

Project ref: `ohmtchfldrqobwrtyhmz`
Project URL: `https://ohmtchfldrqobwrtyhmz.supabase.co`

## Migrations

Apply migrations in order from `supabase/migrations/`.

- `0001_init.sql` — core enums, tables, RLS policies, `handle_new_user`, `dream_stats`
- `0002_storage.sql` — storage buckets and storage RLS
- `0003_harden.sql` — early security-advisor hardening
- `0004_profile_from_metadata.sql` — populate profile handle/name from sign-up metadata
- `0005_videos_readable_by_all_authed.sql` — allow authed users to play feed videos via signed URLs
- `0006_profile_features.sql` — follows, featured dream, `profile_stats`
- `0007_video_title.sql` — per-video update titles
- `0008_help_offer_status.sql` — expanded help-offer lifecycle enum
- `0009_messaging.sql` — conversations, participants, messages, notifications, Realtime
- `0010_help_offer_rpc.sql` — help-offer workflow RPCs and read helpers
- `0011_harden_messaging_functions.sql` — pinned `search_path` and permission hardening
- `0012_revoke_anon_messaging_functions.sql` — authenticated-only messaging RPCs
- `0013_profile_avatar.sql` — `profiles.avatar_url` and avatar remove/read support
- `0014_avatar_storage_rls.sql` — avatar overwrite/remove RLS repair
- `0015_video_shares.sql` — in-app video sharing (`dream_share` messages and `share_dream_video`)
- `0016_harden_video_share_trigger.sql` — keep `on_message_insert()` trigger-only
- `0017_search.sql` — full-text search RPCs and indexes for dreams/profiles
- `0018_one_conversation_per_pair.sql` — one direct 1:1 conversation per user pair; help offers, shares, and texts all route through it
- `0019_security_hardening.sql` — authenticated read hardening, direct-message insert restrictions, safer profile updates, and private Realtime channel policies
- `0020_explore_photo_updates.sql` — mixed-media Explore support: `dream_videos.caption`, `dream_photo_updates`, explicit Data API grants, and the public `dream-images` bucket
- `0021_help_types.sql` — canonical `help_type` enum + `to_help_type()` normalizer, trigger-synced `dreams.help_types`, and `supporter_profiles` (what a user can offer)
- `0022_engagement.sql` — `engagement_events` log, per-viewer `dream_seen` seen-set, `dream_exposure_counters`, and the `log_engagement_batch` ingestion RPC
- `0023_offer_lifecycle.sql` — connection-funnel instrumentation: `help_offers.accepted_at/completed_at` + `help_offer_events` transition log
- `0024_feed_candidates.sql` — recommendation read RPCs: `get_viewer_ranking_profile` and multi-source `get_feed_candidates`
- `0025_comments.sql` — `dream_comments`, counts view, and owner `comment` notifications
- `0026_per_update_comments.sql` — per-update comment threads: `dream_comment_counts` rebuilt per `(dream, video)` with `thread_id`
- `0027_comments_cascade_with_clip.sql` — deleting a clip cascade-deletes its comment thread

Apply all migrations through `0027_comments_cascade_with_clip.sql` for the current app code.

## Applying Migrations

Preferred path in this repo is the configured Supabase MCP server:

```bash
codex mcp add supabase --url "https://mcp.supabase.com/mcp?project_ref=ohmtchfldrqobwrtyhmz"
codex mcp login supabase
```

Then use the Supabase MCP `apply_migration`, `list_migrations`, `execute_sql`, and `get_advisors` tools.

Supabase CLI is also fine:

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref ohmtchfldrqobwrtyhmz
supabase db push
```

After DDL changes, run security advisors and fix new warnings unless they are an intentional existing pattern.

## Tests, Seed, and Reports

- `tests/*.sql` — pgTAP suites (`messaging_test.sql`, `ranking_test.sql`, `comments_test.sql`). Each is self-contained inside one transaction and ends with `rollback`, so they are **safe to run against the hosted project** via the MCP `execute_sql` tool or psql. The final row reports pass/fail counts; `failures` must be 0.
- `seed.sql` — **local development only** (it inserts into `auth.users`; a guard refuses to run against a database with real users). `supabase db reset` applies migrations then this file: 30 supporters with capability profiles + 60 dreams in popular/mid/starved/fresh cohorts + skewed offers and engagement, for inspecting ranked feed output. Seed users sign in with password `password123`.
- `queries/fairness_report.sql` — read-only fairness report: per-dream exposure/offers, the share of 30-day-old dreams with zero offers (the metric the recommendation system is judged on), 7-day exposure-floor attainment, impressions by category, and the offer→accepted→delivered funnel.

## Auth

The app uses Supabase **email + password** auth through `AuthService`.

`profiles` rows are auto-created from `auth.users` by `handle_new_user`. `0004_profile_from_metadata.sql` can populate handle/name from sign-up metadata when present.

## Data Model

```text
auth.users
└── profiles
    ├── follows
    ├── supporter_profiles        (what a user can offer — matching input)
    ├── dreams
    │   ├── journey_steps
    │   ├── dream_videos
    │   │   └── dream_comments    (per-clip threads; cascade with the clip)
    │   ├── dream_photo_updates
    │   ├── supporters
    │   ├── help_offers
    │   │   └── help_offer_events (lifecycle transition log)
    │   └── dream_exposure_counters
    ├── engagement_events         (view/watch/skip/save/… — viewer-local signals)
    ├── dream_seen                (per-viewer seen-set + dismissals)
    ├── conversations
    │   ├── conversation_participants
    │   └── messages
    └── notifications
```

Important tables:

- `profiles` — handle, name, avatar seed, uploaded avatar URL, location, skills
- `dreams` — owner, title, description, category, stage, help tags, featured flag
- `dream_videos` — storage path, poster path, dimensions, primary flag, per-video title, optional caption
- `dream_photo_updates` — dream-attached photo update rows with public `dream-images` object paths, title, optional caption, dimensions, and owner-only writes
- `follows` — follower/followed graph; used by the Discover follow button and share recipient list
- `help_offers` — structured "I can help" offers with lifecycle status and optional conversation
- `conversations` — one direct 1:1 thread per user pair; `dream_id` is retired and always null after `0018`
- `conversation_participants` — membership, roles, read receipts
- `messages` — text/system/share messages; `dream_share` messages carry `shared_dream_id` and `shared_video_id`; direct client inserts may only create plain `text` messages after `0019`
- `notifications` — Activity tab events and unread badge source
- `supporter_profiles` — help types offered, weekly capacity, category interests, stage preferences (own-row RLS; edited in the app's "How You Can Help" profile section)
- `engagement_events` — append-only log (view, watch_progress, complete, skip, offer_help, comment, save, share, follow, not_relevant); writes only via `log_engagement_batch`. These shape ONLY the logging viewer's own affinity — never a dream's global standing
- `dream_seen` — one row per (viewer, dream): first/last seen, seen count, dismissed flag; drives feed exclusion and "Not interested"
- `dream_exposure_counters` — impressions / distinct_viewers / offers_received per dream; written only by SECURITY DEFINER paths; feeds the fairness pass
- `help_offer_events` — offer status transition log with timestamps (the offer_sent → accepted → conversation → support_delivered funnel)
- `dream_comments` — per-update comment threads (`video_id` = the clip; null only for videoless dreams); author-or-owner delete; cascade-deletes with the clip

Views:

- `dream_stats` — supporters/offers per dream
- `profile_stats` — videos/followers/following/offers per profile
- `dream_comment_counts` — one row per comment thread; `thread_id = coalesce(video_id, dream_id)` matches the app's `Dream.feedID`

## RPCs

All cross-user workflow writes go through RPCs so authorization and multi-row writes stay atomic.

- `create_help_offer(p_dream_id, p_skill, p_message)` — creates/reuses an active help offer, routes it into the pair's direct conversation, posts a system message, notifies the owner
- `respond_to_help_offer(p_offer_id, p_status)` — owner advances offer lifecycle, posts system message, notifies supporter
- `cancel_help_offer(p_offer_id)` — supporter cancels their offer, posts system message, notifies owner
- `mark_conversation_read(p_conversation_id)` — updates read receipt and clears unread message notifications
- `mark_notifications_read(p_ids)` — marks selected notifications read
- `mark_all_notifications_read()` — marks all current user's notifications read
- `share_dream_video(p_recipient_id, p_dream_id, p_video_id, p_note)` — creates/reuses the pair's direct 1:1 chat, inserts a `dream_share` message, and lets the message trigger notify the recipient
- `get_or_create_direct_conversation(p_a, p_b)` — internal helper used by RPCs only; do not grant direct client execution
- `log_engagement_batch(p_events)` — batched engagement ingestion (max 100/batch): inserts events, maintains `dream_seen` and exposure counters on `view`, marks dismissed on `not_relevant`
- `get_viewer_ranking_profile()` — one row describing the viewer for the ranker: capabilities, follows, and a category affinity learned from their own last-30-day events (SECURITY INVOKER)
- `get_feed_candidates(p_limit, p_seen_ttl_days, p_underexposed_viewer_floor)` — ~300 raw candidates from independent sources (help-type match, skill overlap, category affinity, geo, followed, fresh, underexposed) with `sources[]` tags and exposure counters; all scoring happens on-device in `Packages/DreamRanking` (SECURITY INVOKER). New sources (e.g. embeddings) are added as another CTE in the union

Trigger-only functions such as `on_message_insert()` should not be executable through `/rpc`.

## Storage

Buckets:

- `dream-videos` — private, 500 MB object limit, playback through signed URLs
- `dream-posters` — public, 5 MB object limit
- `dream-images` — public, 5 MB object limit, compressed photo updates
- `avatars` — public, 2 MB object limit

Paths:

```text
dream-videos/{user_id}/{dream_id}/{video_id}.mp4
dream-posters/{user_id}/{dream_id}/{video_id}.jpg
dream-images/{user_id}/{dream_id}/{image_id}.jpg
avatars/{user_id}/avatar.jpg
```

The first folder must be the lowercased user id. Storage RLS checks:

```sql
(storage.foldername(name))[1] = auth.uid()::text
```

Postgres renders `auth.uid()` lowercase, while Swift's `UUID.uuidString` is uppercase by default. Swift upload paths must call `.uuidString.lowercased()`.

## Realtime

Realtime is enabled for:

- `messages`
- `notifications`
- `conversation_participants`
- `conversations`
- `help_offers`

`ActivityRepository` subscribes to notification inserts/updates for the signed-in user. `ChatRepository` subscribes per open conversation for message inserts, participant updates/read receipts, typing broadcasts, and presence on a private `conversation:<uuid>` channel. The private channel authorization policies live on `realtime.messages` in `0019_security_hardening.sql`; the Swift client must set `isPrivate = true`.

Cost conventions:

- Debounce Activity reloads after notification bursts.
- Debounce `mark_conversation_read`.
- Throttle typing broadcasts.
- Prefer optimistic local updates for read state.

## Swift Integration

| Layer | File |
|---|---|
| Config | `Dream/Config/SupabaseConfig.swift` |
| Client singleton | `Dream/Services/SupabaseService.swift` |
| Auth | `Dream/Services/AuthService.swift` |
| Core DTOs | `Dream/Services/DreamDTO.swift` |
| Messaging DTOs | `Dream/Services/MessagingDTO.swift` |
| Feed CRUD + ranked feed | `Dream/Services/DreamRepository.swift` |
| Explore media (ranked grid) | `Dream/Services/ExploreMediaRepository.swift` |
| Ranking DTOs | `Dream/Services/RankingDTO.swift` |
| Recommendation RPCs | `Dream/Services/RecommendationRepository.swift` |
| Ranked queue | `Dream/Services/FeedQueueService.swift` |
| Engagement batching | `Dream/Services/EngagementLogger.swift` |
| Comments | `Dream/Services/CommentRepository.swift` |
| Pure ranker (package) | `Packages/DreamRanking/` |
| Profiles/follows | `Dream/Services/ProfileRepository.swift` |
| Activity aggregation | `Dream/Services/ActivityRepository.swift` |
| Chat realtime | `Dream/Services/ChatRepository.swift` |
| Help-offer RPCs | `Dream/Services/HelpOfferRepository.swift` |
| In-app video sharing | `Dream/Services/VideoShareRepository.swift` |
| Avatar upload | `Dream/Services/AvatarUploader.swift` |
| Video upload | `Dream/Services/VideoUploader.swift` |
| Photo update upload | `Dream/Services/DreamImageUploader.swift` |
| Native export/share | `Dream/Services/VideoExporter.swift` |

## Notes

- Do not add a blanket `.limit()` to fan-out `.in(...)` queries in `DreamRepository.fetchContext`; it can silently drop feed cards.
- Keep `dream_photo_updates` grants explicit for `authenticated`; Data API exposure is not guaranteed by RLS alone on newer Supabase projects.
- Keep video prefetch tight (`[0, 1, -1]`) because every prefetched card eagerly buffers video.
- Never create conversations directly from Swift. Use `create_help_offer` or `share_dream_video`; both route through `get_or_create_direct_conversation`.
- Never write `engagement_events` / `dream_seen` / `dream_exposure_counters` directly from Swift — everything goes through `log_engagement_batch` so the seen-set and counters stay consistent.
- Keep Realtime chat channels private and topic-scoped to `conversation:<uuid>`.
