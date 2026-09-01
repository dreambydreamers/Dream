-- Comments become per-update: each clip (cover video or update video) owns
-- its own thread. dream_comments.video_id already identifies the clip; this
-- migration makes it load-bearing:
--   * backfills legacy null video_id rows onto the dream's cover clip
--     (dreams with no videos keep null — their thread keys on the dream)
--   * rebuilds dream_comment_counts per (dream, video), exposing thread_id =
--     coalesce(video_id, dream_id) — the same key the app's feed cards use
--     (Dream.feedID = videoId ?? id).

update public.dream_comments c
set video_id = v.id
from public.dream_videos v
where c.video_id is null
  and v.dream_id = c.dream_id
  and v.is_primary;

drop view if exists public.dream_comment_counts;

create view public.dream_comment_counts
with (security_invoker = on) as
select
    dream_id,
    video_id,
    coalesce(video_id, dream_id) as thread_id,
    count(*)::bigint as comments_count
from public.dream_comments
group by dream_id, video_id;

grant select on public.dream_comment_counts to authenticated;
