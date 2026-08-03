-- Comments become per-photo as well as per-clip.
--
-- 0026 made every video clip own its thread. Photo updates had no equivalent,
-- so every photo of a dream fell back to the dream-level thread and all of them
-- showed each other's comments. `photo_id` gives a photo update the same
-- treatment a clip already had, and the thread key becomes
-- coalesce(video_id, photo_id, dream_id) — still the dream itself for the
-- gradient (no-media) cards.

alter table public.dream_comments
    add column if not exists photo_id uuid
        references public.dream_photo_updates(id) on delete cascade;

create index if not exists dream_comments_photo_idx
    on public.dream_comments (photo_id, created_at desc);

-- A comment hangs off one medium at most; both set would make thread_id lie.
alter table public.dream_comments
    drop constraint if exists dream_comments_single_medium;
alter table public.dream_comments
    add constraint dream_comments_single_medium
    check (video_id is null or photo_id is null);

drop view if exists public.dream_comment_counts;

create view public.dream_comment_counts
with (security_invoker = on) as
select
    dream_id,
    video_id,
    photo_id,
    coalesce(video_id, photo_id, dream_id) as thread_id,
    count(*)::bigint as comments_count
from public.dream_comments
group by dream_id, video_id, photo_id;

grant select on public.dream_comment_counts to authenticated;
