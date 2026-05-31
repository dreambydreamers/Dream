# Dream Supabase Backend

This directory holds the SQL schema and storage setup for the Dream Supabase project.

Project: `https://qlrqcymqtxrrpekdzgxx.supabase.co`

## What's here

- `migrations/0001_init.sql` — tables, enums, RLS policies, `handle_new_user` trigger, `dream_stats` view
- `migrations/0002_storage.sql` — buckets (`dream-videos`, `dream-posters`, `avatars`) and storage policies

## Initial setup (one-time)

### 1. Apply the migrations

The simplest path is the dashboard SQL editor:

1. Open https://supabase.com/dashboard/project/qlrqcymqtxrrpekdzgxx/sql
2. Paste the contents of `migrations/0001_init.sql`, run it.
3. Paste the contents of `migrations/0002_storage.sql`, run it.

Or with the Supabase CLI:

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref qlrqcymqtxrrpekdzgxx
supabase db push   # applies any pending migrations in supabase/migrations/
```

### 2. Enable anonymous sign-in

Dashboard → Authentication → Providers → **Anonymous Sign-ins** → toggle **on**.

This is what `AuthService.ensureSignedIn()` calls. Sessions persist on-device via the SDK's keychain storage.

### 3. (Later) Apple Sign-In

When you have an Apple Developer account:

1. Apple Developer portal → create a Services ID for the bundle (e.g. `com.gabrilo.Dream.signin`)
2. Configure Apple as an OAuth provider in Supabase dashboard with the Services ID, Team ID, key ID, and `.p8` key contents
3. Switch `OnboardingScreen` to call `supabase.auth.signInWithIdToken(provider: .apple, idToken:)` using the credential from `ASAuthorizationAppleIDCredential`
4. Anonymous → Apple link: call `supabase.auth.linkIdentity(provider: .apple)` to upgrade the existing anonymous user

## Xcode setup

The Swift side expects the `supabase-swift` SPM package.

1. Open `Dream.xcodeproj` in Xcode
2. File → Add Package Dependencies…
3. URL: `https://github.com/supabase/supabase-swift`
4. Dependency Rule: **Up to Next Major** from `2.0.0`
5. Add product **Supabase** to the **Dream** target

After that, build — the `No such module 'Supabase'` errors will clear.

## Architecture summary

| Layer | File |
|---|---|
| Config | `Dream/Config/SupabaseConfig.swift` |
| Client singleton | `Dream/Services/SupabaseService.swift` |
| Anonymous auth | `Dream/Services/AuthService.swift` |
| Codable DTOs | `Dream/Services/DreamDTO.swift` |
| Feed CRUD | `Dream/Services/DreamRepository.swift` |
| Video upload | `Dream/Services/VideoUploader.swift` |

## Data model at a glance

```
auth.users  (managed by Supabase Auth)
    └── profiles            (1:1 with auth.users, auto-created via trigger)
            ├── dreams      (owner_id → profiles)
            │     ├── journey_steps
            │     ├── dream_videos      (storage path → dream-videos bucket)
            │     ├── supporters        (m:n with profiles)
            │     └── help_offers       (offers from profiles)
            └── …
```

Counts (`supporters`, `offers`) are computed via the `dream_stats` view, not stored.

## RLS summary

- **Public read:** `dreams`, `journey_steps`, `dream_videos`, `supporters`, `profiles`, `dream_stats`
- **Owner-only write:** `dreams`, `journey_steps`, `dream_videos` (via `dreams.owner_id = auth.uid()`)
- **Self-only write:** `profiles`, `supporters`, `help_offers` (as the supporter author)
- **Owner can update offer status** on their own dreams

## Storage paths

```
dream-videos/{user_id}/{dream_id}/{video_id}.mp4    (private — signed URLs)
dream-posters/{user_id}/{dream_id}/{video_id}.jpg   (public)
avatars/{user_id}/{filename}                        (public)
```

The first path segment (`user_id`) is enforced by RLS via `storage.foldername(name)[1] = auth.uid()::text`.

## Next wiring steps (Swift side)

1. Add SPM package (above)
2. In `DreamApp.swift`, call `await AuthService.shared.ensureSignedIn()` on launch
3. Replace `Dream.samples` in `DiscoverScreen` with `@StateObject var repo = DreamRepository.shared` and call `await repo.loadFeed()` in `.task { }`
4. In `CreateDreamScreen.swift`, on submit:
   - `let id = try await DreamRepository.shared.createDream(...)`
   - if a video was picked: `try await VideoUploader.shared.upload(localVideoURL:, dreamId: id)`
