-- Likes on feed videos.
--
-- Keyed per *clip*, not per dream, matching comments (0026) and the app's feed
-- cards: a dream's cover video and each update video are separate cards, so
-- they carry separate like counts. `thread_id` is the same key the client uses
-- as `Dream.feedID` (videoId ?? dreamId).
--
-- Note on the engagement invariant (0022): the per-dream like *count* lives
-- here, in its own table, not in engagement_events. The 'like' engagement event
-- added at the bottom feeds only the liking viewer's own affinity profile, in
-- keeping with "nothing aggregates engagement_events into a per-dream quality
-- signal".

create table if not exists public.dream_likes (
    id uuid primary key default gen_random_uuid(),
    dream_id uuid not null references public.dreams(id) on delete cascade,
    -- The clip that was liked. Nullable for dreams with no video (gradient
    -- cards), which like against the dream itself.
    video_id uuid references public.dream_videos(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    -- Stored so the "one like per viewer per card" rule is a real constraint.
    -- A plain unique on (user_id, dream_id, video_id) would not dedupe the
    -- null-video rows, since nulls compare distinct.
    thread_id uuid generated always as (coalesce(video_id, dream_id)) stored,
    created_at timestamptz not null default now()
);

create unique index if not exists dream_likes_one_per_viewer_idx
    on public.dream_likes (user_id, thread_id);

create index if not exists dream_likes_dream_idx
    on public.dream_likes (dream_id, created_at desc);

alter table public.dream_likes enable row level security;

grant select, insert, delete on public.dream_likes to authenticated;

drop policy if exists "likes readable by signed-in users" on public.dream_likes;
create policy "likes readable by signed-in users"
    on public.dream_likes
    for select
    to authenticated
    using (true);

drop policy if exists "users insert own likes" on public.dream_likes;
create policy "users insert own likes"
    on public.dream_likes
    for insert
    to authenticated
    with check (user_id = (select auth.uid()));

-- Unlike is the author's own action only; a dream owner cannot remove a like
-- from their dream (unlike comments, where they can moderate).
drop policy if exists "users delete own likes" on public.dream_likes;
create policy "users delete own likes"
    on public.dream_likes
    for delete
    to authenticated
    using (user_id = (select auth.uid()));

-- Per-clip like counts for feed badges. Mirrors dream_comment_counts.
create or replace view public.dream_like_counts
with (security_invoker = on) as
select
    dream_id,
    video_id,
    thread_id,
    count(*)::bigint as likes_count
from public.dream_likes
group by dream_id, video_id, thread_id;

grant select on public.dream_like_counts to authenticated;

-- Notify the dream owner, skipping self-likes. SECURITY DEFINER because
-- clients have no insert grant on notifications.
--
-- Deliberately fires only on the viewer's *first* like of a given dream, so
-- re-liking after an unlike doesn't re-notify. Likes are far higher-frequency
-- than comments and would otherwise dominate the activity feed.
create or replace function public.notify_dream_like()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_owner uuid;
    v_seen boolean;
begin
    select owner_id into v_owner from public.dreams where id = new.dream_id;
    if v_owner is null or v_owner = new.user_id then
        return null;
    end if;

    select exists (
        select 1 from public.notifications
        where user_id = v_owner
          and type = 'like'
          and actor_id = new.user_id
          and dream_id = new.dream_id
    ) into v_seen;

    if not v_seen then
        insert into public.notifications (user_id, type, actor_id, dream_id, preview)
        values (v_owner, 'like', new.user_id, new.dream_id, '');
    end if;

    return null;
end;
$$;

revoke execute on function public.notify_dream_like() from public, anon, authenticated;

drop trigger if exists dream_likes_notify on public.dream_likes;
create trigger dream_likes_notify
    after insert on public.dream_likes
    for each row
    execute function public.notify_dream_like();

-- Viewer-affinity signal only (see the header note).
alter type public.engagement_event_type add value if not exists 'like';
