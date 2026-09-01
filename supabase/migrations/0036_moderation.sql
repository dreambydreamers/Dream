-- 0036_moderation.sql
-- Production-readiness audit (2026-08): blocking and reporting.
--
-- Dream carries user-generated video, photos, comments and unrestricted DMs
-- with no way to block an abusive user or report content. App Store Guideline
-- 1.2 requires both for UGC apps, and it is a real safety gap regardless.
--
-- Enforcement is in the database, not the UI, so a blocked user stays blocked
-- no matter which client talks to the API. Note that with zero rows in
-- `user_blocks` every policy below evaluates exactly as it did before, so this
-- migration is a no-op for existing behaviour until someone blocks someone.

-- =========================================================
-- 1. Tables
-- =========================================================

create table if not exists public.user_blocks (
    blocker_id uuid not null references public.profiles(id) on delete cascade,
    blocked_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    constraint user_blocks_no_self check (blocker_id <> blocked_id)
);

-- The reverse lookup is the hot one: "does anyone block me?" runs inside RLS.
create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;
grant select, insert, delete on public.user_blocks to authenticated;

-- Only the blocker sees their own list. Deliberately NOT visible to the
-- blocked party — being told you were blocked is itself a harassment vector.
drop policy if exists "users read their own blocks" on public.user_blocks;
create policy "users read their own blocks"
    on public.user_blocks for select to authenticated
    using (blocker_id = (select auth.uid()));

drop policy if exists "users create their own blocks" on public.user_blocks;
create policy "users create their own blocks"
    on public.user_blocks for insert to authenticated
    with check (blocker_id = (select auth.uid()));

drop policy if exists "users remove their own blocks" on public.user_blocks;
create policy "users remove their own blocks"
    on public.user_blocks for delete to authenticated
    using (blocker_id = (select auth.uid()));

do $$ begin
    create type public.report_target_type as enum
        ('dream', 'video', 'photo', 'comment', 'message', 'profile');
exception when duplicate_object then null; end $$;

do $$ begin
    create type public.report_reason as enum
        ('spam', 'harassment', 'hate', 'violence', 'sexual_content',
         'self_harm', 'misinformation', 'impersonation', 'intellectual_property', 'other');
exception when duplicate_object then null; end $$;

do $$ begin
    create type public.report_status as enum ('pending', 'reviewing', 'actioned', 'dismissed');
exception when duplicate_object then null; end $$;

create table if not exists public.content_reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references public.profiles(id) on delete cascade,
    -- Denormalised so a report survives the reported content being deleted,
    -- which is the first thing an abuser does.
    reported_user_id uuid references public.profiles(id) on delete set null,
    target_type public.report_target_type not null,
    target_id uuid not null,
    reason public.report_reason not null,
    note text check (note is null or char_length(note) <= 1000),
    -- Snapshot of what was reported, for review after deletion.
    content_excerpt text check (content_excerpt is null or char_length(content_excerpt) <= 2000),
    status public.report_status not null default 'pending',
    created_at timestamptz not null default now(),
    reviewed_at timestamptz,
    unique (reporter_id, target_type, target_id)
);

create index if not exists content_reports_triage_idx
    on public.content_reports (status, created_at desc);
create index if not exists content_reports_reported_user_idx
    on public.content_reports (reported_user_id, created_at desc);

alter table public.content_reports enable row level security;
grant select, insert on public.content_reports to authenticated;

-- A reporter can file and can see what they filed. Nobody can edit or delete
-- through the API — triage happens with the service role.
drop policy if exists "users read their own reports" on public.content_reports;
create policy "users read their own reports"
    on public.content_reports for select to authenticated
    using (reporter_id = (select auth.uid()));

drop policy if exists "users file their own reports" on public.content_reports;
create policy "users file their own reports"
    on public.content_reports for insert to authenticated
    with check (reporter_id = (select auth.uid()) and status = 'pending');

-- =========================================================
-- 2. The predicate everything else is built on
-- =========================================================
-- SECURITY DEFINER because it must see blocks in BOTH directions, while the
-- table's own RLS only exposes the caller's own rows. Blocking is symmetric in
-- effect: neither party sees or can reach the other.

create or replace function public.is_blocked_pair(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select a is not null and b is not null and exists (
        select 1 from public.user_blocks
        where (blocker_id = a and blocked_id = b)
           or (blocker_id = b and blocked_id = a)
    );
$$;

revoke execute on function public.is_blocked_pair(uuid, uuid) from public, anon;
-- Must be executable by `authenticated`: it is referenced from RLS policies,
-- which are evaluated with the querying role's privileges.
grant execute on function public.is_blocked_pair(uuid, uuid) to authenticated;

-- =========================================================
-- 3. Read paths: blocked users' content disappears
-- =========================================================
-- Only the block condition is added; the rest of each policy is unchanged.

drop policy if exists "profiles are readable by everyone" on public.profiles;
create policy "profiles are readable by everyone"
    on public.profiles for select to authenticated
    using (
        id = (select auth.uid())
        or not public.is_blocked_pair(id, (select auth.uid()))
    );

drop policy if exists "dreams are readable by everyone" on public.dreams;
create policy "dreams are readable by everyone"
    on public.dreams for select to authenticated
    using (not public.is_blocked_pair(owner_id, (select auth.uid())));

-- Media and timelines inherit visibility from their dream: RLS applies to the
-- `dreams` reference inside these policies, so a hidden dream hides its media
-- without repeating the block predicate.
drop policy if exists "dream videos are readable by everyone" on public.dream_videos;
create policy "dream videos are readable by everyone"
    on public.dream_videos for select to authenticated
    using (exists (select 1 from public.dreams d where d.id = dream_videos.dream_id));

drop policy if exists "dream photo updates are readable by signed-in users" on public.dream_photo_updates;
create policy "dream photo updates are readable by signed-in users"
    on public.dream_photo_updates for select to authenticated
    using (exists (select 1 from public.dreams d where d.id = dream_photo_updates.dream_id));

drop policy if exists "journey steps are readable by everyone" on public.journey_steps;
create policy "journey steps are readable by everyone"
    on public.journey_steps for select to authenticated
    using (exists (select 1 from public.dreams d where d.id = journey_steps.dream_id));

-- A blocked user's comments vanish from every thread, and comments on a
-- hidden dream go with it.
drop policy if exists "comments readable by signed-in users" on public.dream_comments;
create policy "comments readable by signed-in users"
    on public.dream_comments for select to authenticated
    using (
        not public.is_blocked_pair(user_id, (select auth.uid()))
        and exists (select 1 from public.dreams d where d.id = dream_comments.dream_id)
    );

-- =========================================================
-- 4. Write paths: no contact in either direction
-- =========================================================

drop policy if exists "users follow as themselves" on public.follows;
create policy "users follow as themselves"
    on public.follows for insert
    with check (
        (select auth.uid()) = follower_id
        and not public.is_blocked_pair(follower_id, followed_id)
    );

-- Messaging is a trigger rather than a policy so it also covers the SECURITY
-- DEFINER RPCs (share_dream_video, create_help_offer), which bypass RLS.
create or replace function public.reject_blocked_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if exists (
        select 1
        from public.conversation_participants cp
        where cp.conversation_id = new.conversation_id
          and cp.user_id <> new.sender_id
          and public.is_blocked_pair(cp.user_id, new.sender_id)
    ) then
        raise exception 'You can no longer message this person.'
            using errcode = '42501';
    end if;
    return new;
end;
$$;

revoke execute on function public.reject_blocked_message() from public, anon, authenticated;

drop trigger if exists messages_reject_blocked on public.messages;
create trigger messages_reject_blocked
    before insert on public.messages
    for each row
    execute function public.reject_blocked_message();

-- Likes and comments on a blocked party's dream.
create or replace function public.reject_blocked_engagement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_owner uuid;
begin
    select owner_id into v_owner from public.dreams where id = new.dream_id;
    if v_owner is not null and public.is_blocked_pair(v_owner, new.user_id) then
        raise exception 'This content is unavailable.' using errcode = '42501';
    end if;
    return new;
end;
$$;

revoke execute on function public.reject_blocked_engagement() from public, anon, authenticated;

drop trigger if exists dream_comments_reject_blocked on public.dream_comments;
create trigger dream_comments_reject_blocked
    before insert on public.dream_comments
    for each row
    execute function public.reject_blocked_engagement();

drop trigger if exists dream_likes_reject_blocked on public.dream_likes;
create trigger dream_likes_reject_blocked
    before insert on public.dream_likes
    for each row
    execute function public.reject_blocked_engagement();

-- =========================================================
-- 5. SECURITY DEFINER RPCs bypass RLS — block them explicitly
-- =========================================================

create or replace function public.create_help_offer(
    p_dream_id uuid,
    p_skill text,
    p_message text default ''
)
returns table (offer_id uuid, conversation_id uuid, already_existed boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- Body is the deployed 0018 definition verbatim; the only change is the
-- is_blocked_pair guard below. Do not "tidy" the dedupe status filter or the
-- message/notification wording — the pgTAP messaging suite asserts them.
declare
    v_caller uuid := auth.uid();
    v_owner uuid;
    v_offer uuid;
    v_conv uuid;
    v_body text;
begin
    if v_caller is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;

    select owner_id into v_owner from dreams where id = p_dream_id;
    if v_owner is null then
        raise exception 'Dream not found' using errcode = 'P0002';
    end if;
    if v_owner = v_caller then
        raise exception 'You cannot offer help on your own dream' using errcode = '42501';
    end if;
    if public.is_blocked_pair(v_owner, v_caller) then
        raise exception 'This dream is unavailable.' using errcode = '42501';
    end if;

    -- Dedupe: reuse any active offer (and its conversation) from this supporter.
    select id, help_offers.conversation_id into v_offer, v_conv
    from help_offers
    where dream_id = p_dream_id
      and supporter_id = v_caller
      and status in ('pending', 'accepted', 'in_progress')
    limit 1;

    if v_offer is not null then
        return query select v_offer, v_conv, true;
        return;
    end if;

    v_conv := get_or_create_direct_conversation(v_caller, v_owner);

    insert into help_offers (dream_id, supporter_id, skill, message, status, conversation_id)
    values (p_dream_id, v_caller, p_skill, coalesce(p_message, ''), 'pending', v_conv)
    returning id into v_offer;

    v_body := 'Offered to help with ' || p_skill
              || case when coalesce(p_message, '') <> '' then ': ' || p_message else '' end;
    insert into messages (conversation_id, sender_id, body, kind)
    values (v_conv, v_caller, v_body, 'system');

    insert into notifications (user_id, type, actor_id, dream_id, offer_id, conversation_id, preview)
    values (v_owner, 'offer_received', v_caller, p_dream_id, v_offer, v_conv,
            'New offer to help with ' || p_skill);

    return query select v_offer, v_conv, false;
end;
$$;

revoke execute on function public.create_help_offer(uuid, text, text) from public, anon;
grant execute on function public.create_help_offer(uuid, text, text) to authenticated;

create or replace function public.share_dream_video(
    p_recipient_id uuid,
    p_dream_id uuid,
    p_video_id uuid default null,
    p_note text default ''
)
returns table (conversation_id uuid, message_id uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_caller uuid := auth.uid();
    v_recipient_exists boolean;
    v_dream_title text;
    v_video_title text;
    v_conv uuid;
    v_msg uuid;
    v_body text;
begin
    if v_caller is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;
    if p_recipient_id is null or p_recipient_id = v_caller then
        raise exception 'Pick someone else to share with' using errcode = '22023';
    end if;

    select exists (select 1 from profiles where id = p_recipient_id)
        into v_recipient_exists;
    if not v_recipient_exists then
        raise exception 'Recipient not found' using errcode = 'P0002';
    end if;

    if public.is_blocked_pair(p_recipient_id, v_caller) then
        raise exception 'You can no longer message this person.' using errcode = '42501';
    end if;

    select title into v_dream_title from dreams where id = p_dream_id;
    if v_dream_title is null then
        raise exception 'Dream not found' using errcode = 'P0002';
    end if;

    if p_video_id is not null then
        select coalesce(title, v_dream_title)
            into v_video_title
        from dream_videos
        where id = p_video_id and dream_id = p_dream_id;

        if v_video_title is null then
            raise exception 'Video not found' using errcode = 'P0002';
        end if;
    else
        v_video_title := v_dream_title;
    end if;

    v_conv := get_or_create_direct_conversation(v_caller, p_recipient_id);

    v_body := 'Shared "' || v_video_title || '"';
    if coalesce(trim(p_note), '') <> '' then
        v_body := v_body || ': ' || trim(p_note);
    end if;

    insert into messages (
        conversation_id, sender_id, body, kind, shared_dream_id, shared_video_id
    )
    values (
        v_conv, v_caller, v_body, 'dream_share', p_dream_id, p_video_id
    )
    returning id into v_msg;

    return query select v_conv, v_msg;
end;
$$;

revoke execute on function public.share_dream_video(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.share_dream_video(uuid, uuid, uuid, text) to authenticated;

-- Search is SECURITY DEFINER (it bypasses RLS), so the block filter that the
-- table policies now apply has to be repeated here by hand.
create or replace function public.search_dreams(query text)
returns table (
  id          uuid,
  title       text,
  description text,
  category    text,
  owner_id    uuid,
  owner_name  text,
  owner_handle text,
  avatar_seed  int,
  avatar_url   text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    d.id,
    d.title,
    d.description,
    d.category::text,
    d.owner_id,
    p.name        as owner_name,
    p.handle      as owner_handle,
    p.avatar_seed,
    p.avatar_url
  from dreams d
  left join profiles p on p.id = d.owner_id
  where d.fts @@ plainto_tsquery('english', query)
    and not public.is_blocked_pair(d.owner_id, auth.uid())
  order by ts_rank(d.fts, plainto_tsquery('english', query)) desc
  limit 20;
$$;

create or replace function public.search_profiles(query text)
returns table (
  id          uuid,
  name        text,
  handle      text,
  location    text,
  avatar_seed  int,
  avatar_url   text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id, name, handle, location, avatar_seed, avatar_url
  from profiles
  where fts @@ plainto_tsquery('simple', query)
    and not public.is_blocked_pair(id, auth.uid())
  order by ts_rank(fts, plainto_tsquery('simple', query)) desc
  limit 10;
$$;

revoke execute on function public.search_dreams(text)  from public, anon;
revoke execute on function public.search_profiles(text) from public, anon;
grant execute on function public.search_dreams(text)  to authenticated;
grant execute on function public.search_profiles(text) to authenticated;

-- =========================================================
-- 6. Blocking is an action, not just a row
-- =========================================================
-- Drops any follow edge in either direction so the block takes effect on the
-- follower lists and the in-app share recipient list immediately.

create or replace function public.block_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_caller uuid := auth.uid();
begin
    if v_caller is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;
    if p_user_id is null or p_user_id = v_caller then
        raise exception 'You cannot block yourself' using errcode = '22023';
    end if;
    if not exists (select 1 from public.profiles where id = p_user_id) then
        raise exception 'User not found' using errcode = 'P0002';
    end if;

    insert into public.user_blocks (blocker_id, blocked_id)
    values (v_caller, p_user_id)
    on conflict do nothing;

    delete from public.follows
    where (follower_id = v_caller and followed_id = p_user_id)
       or (follower_id = p_user_id and followed_id = v_caller);
end;
$$;

revoke execute on function public.block_user(uuid) from public, anon;
grant execute on function public.block_user(uuid) to authenticated;
