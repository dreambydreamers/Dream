-- Comments on dreams (surfaced per feed video). Engagement instrumentation:
-- posting a comment also logs a 'comment' engagement event client-side, which
-- feeds the commenting viewer's own affinity profile.

create table if not exists public.dream_comments (
    id uuid primary key default gen_random_uuid(),
    dream_id uuid not null references public.dreams(id) on delete cascade,
    -- The specific clip the comment was left on, when known (feed cards are
    -- per-video). Nullable: gradient cards / deleted clips keep the comment.
    video_id uuid references public.dream_videos(id) on delete set null,
    user_id uuid not null references public.profiles(id) on delete cascade,
    body text not null check (char_length(btrim(body)) between 1 and 1000),
    created_at timestamptz not null default now()
);

create index if not exists dream_comments_dream_idx
    on public.dream_comments (dream_id, created_at desc);

create index if not exists dream_comments_user_idx
    on public.dream_comments (user_id, created_at desc);

alter table public.dream_comments enable row level security;

grant select, insert, delete on public.dream_comments to authenticated;

drop policy if exists "comments readable by signed-in users" on public.dream_comments;
create policy "comments readable by signed-in users"
    on public.dream_comments
    for select
    to authenticated
    using (true);

drop policy if exists "users insert own comments" on public.dream_comments;
create policy "users insert own comments"
    on public.dream_comments
    for insert
    to authenticated
    with check (user_id = (select auth.uid()));

-- Author can delete their comment; the dream owner can moderate their dream.
drop policy if exists "author or dream owner deletes comments" on public.dream_comments;
create policy "author or dream owner deletes comments"
    on public.dream_comments
    for delete
    to authenticated
    using (
        user_id = (select auth.uid())
        or exists (
            select 1 from public.dreams d
            where d.id = dream_id
              and d.owner_id = (select auth.uid())
        )
    );

-- Per-dream comment counts for feed badges.
create or replace view public.dream_comment_counts
with (security_invoker = on) as
select dream_id, count(*)::bigint as comments_count
from public.dream_comments
group by dream_id;

grant select on public.dream_comment_counts to authenticated;

-- Notify the dream owner (skipping self-comments). SECURITY DEFINER because
-- clients have no insert grant on notifications.
create or replace function public.notify_dream_comment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_owner uuid;
begin
    select owner_id into v_owner from public.dreams where id = new.dream_id;
    if v_owner is not null and v_owner <> new.user_id then
        insert into public.notifications (user_id, type, actor_id, dream_id, preview)
        values (v_owner, 'comment', new.user_id, new.dream_id, left(btrim(new.body), 140));
    end if;
    return null;
end;
$$;

revoke execute on function public.notify_dream_comment() from public, anon, authenticated;

drop trigger if exists dream_comments_notify on public.dream_comments;
create trigger dream_comments_notify
    after insert on public.dream_comments
    for each row
    execute function public.notify_dream_comment();
