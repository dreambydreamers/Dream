# Dream Supabase Backend

This directory holds the SQL schema, RLS policies, storage setup, Realtime config, and RPC workflows for the Dream Supabase project.

Project ref: `qlrqcymqtxrrpekdzgxx`
Project URL: `https://qlrqcymqtxrrpekdzgxx.supabase.co`

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

The live project currently has migrations through `0016_harden_video_share_trigger`.

## Applying Migrations

Preferred path in this repo is the configured Supabase MCP server:

```bash
codex mcp add supabase --url "https://mcp.supabase.com/mcp?project_ref=qlrqcymqtxrrpekdzgxx"
codex mcp login supabase
```

Then use the Supabase MCP `apply_migration`, `list_migrations`, `execute_sql`, and `get_advisors` tools.

Supabase CLI is also fine:

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref qlrqcymqtxrrpekdzgxx
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
- `dream_videos` — storage path, poster path, dimensions, primary flag, per-video title
- `follows` — follower/followed graph; used by the Discover follow button and share recipient list
- `help_offers` — structured "I can help" offers with lifecycle status and optional conversation
- `conversations` — help-offer chats (`dream_id` set) or direct share chats (`dream_id` null)
- `conversation_participants` — membership, roles, read receipts
- `messages` — text/system/share messages; `dream_share` messages carry `shared_dream_id` and `shared_video_id`
- `notifications` — Activity tab events and unread badge source

Views:

- `dream_stats` — supporters/offers per dream
- `profile_stats` — videos/followers/following/offers per profile

## RPCs

All cross-user workflow writes go through RPCs so authorization and multi-row writes stay atomic.

- `create_help_offer(p_dream_id, p_skill, p_message)` — creates/reuses an active help offer, opens a help conversation, posts a system message, notifies the owner
- `respond_to_help_offer(p_offer_id, p_status)` — owner advances offer lifecycle, posts system message, notifies supporter
- `cancel_help_offer(p_offer_id)` — supporter cancels their offer, posts system message, notifies owner
- `mark_conversation_read(p_conversation_id)` — updates read receipt and clears unread message notifications
- `mark_notifications_read(p_ids)` — marks selected notifications read
- `mark_all_notifications_read()` — marks all current user's notifications read
- `share_dream_video(p_recipient_id, p_dream_id, p_video_id, p_note)` — creates/reuses a direct 1:1 chat, inserts a `dream_share` message, and lets the message trigger notify the recipient

Trigger-only functions such as `on_message_insert()` should not be executable through `/rpc`.

## Storage

Buckets:

- `dream-videos` — private, 500 MB object limit, playback through signed URLs
- `dream-posters` — public, 5 MB object limit
- `avatars` — public, 2 MB object limit

Paths:

```text
dream-videos/{user_id}/{dream_id}/{video_id}.mp4
dream-posters/{user_id}/{dream_id}/{video_id}.jpg
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

`ActivityRepository` subscribes to notification inserts/updates for the signed-in user. `ChatRepository` subscribes per open conversation for message inserts, participant updates/read receipts, typing broadcasts, and presence.

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
| Profiles/follows | `Dream/Services/ProfileRepository.swift` |
| Activity aggregation | `Dream/Services/ActivityRepository.swift` |
| Chat realtime | `Dream/Services/ChatRepository.swift` |
| Help-offer RPCs | `Dream/Services/HelpOfferRepository.swift` |
| In-app video sharing | `Dream/Services/VideoShareRepository.swift` |
| Avatar upload | `Dream/Services/AvatarUploader.swift` |
| Video upload | `Dream/Services/VideoUploader.swift` |
| Native export/share | `Dream/Services/VideoExporter.swift` |

## Notes

- Do not add a blanket `.limit()` to fan-out `.in(...)` queries in `DreamRepository.fetchContext`; it can silently drop feed cards.
- Keep video prefetch tight (`[0, 1, -1]`) because every prefetched card eagerly buffers video.
- Keep share chats separate from help-offer chats by reusing only conversations with `dream_id is null`.
