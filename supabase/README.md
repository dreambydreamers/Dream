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

Apply all migrations through `0020_explore_photo_updates.sql` for the current app code.

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

## Auth

The app uses Supabase **email + password** auth through `AuthService`.

`profiles` rows are auto-created from `auth.users` by `handle_new_user`. `0004_profile_from_metadata.sql` can populate handle/name from sign-up metadata when present.

## Data Model

```text
auth.users
└── profiles
    ├── follows
    ├── dreams
    │   ├── journey_steps
    │   ├── dream_videos
    │   ├── dream_photo_updates
    │   ├── supporters
    │   └── help_offers
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

Views:

- `dream_stats` — supporters/offers per dream
- `profile_stats` — videos/followers/following/offers per profile

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
| Feed CRUD | `Dream/Services/DreamRepository.swift` |
| Explore media | `Dream/Services/ExploreMediaRepository.swift` |
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
- Keep Realtime chat channels private and topic-scoped to `conversation:<uuid>`.
