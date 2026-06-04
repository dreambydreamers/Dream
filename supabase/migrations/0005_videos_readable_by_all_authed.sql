-- Make dream videos viewable by every signed-in user.
--
-- The Discover feed is a public, TikTok-style feed: any signed-in user watches
-- everyone's dream videos. The original SELECT policy only let the *owner* read
-- (and therefore mint signed URLs for) their own videos, so a second account
-- saw posters but no playback. Relax SELECT to any authenticated user.
--
-- The bucket stays PRIVATE (no anonymous/public listing) and writes/deletes stay
-- owner-only; playback still requires a valid signed URL minted via the API.

drop policy if exists "auth users read own videos" on storage.objects;

create policy "authed users read dream videos"
on storage.objects for select
using (
    bucket_id = 'dream-videos'
    and auth.role() = 'authenticated'
);
