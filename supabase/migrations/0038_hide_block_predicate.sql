-- 0038_hide_block_predicate.sql
-- Follow-up to 0036: stop `is_blocked_pair` from being an oracle.
--
-- 0036 put the predicate in `public` and granted EXECUTE to `authenticated`,
-- which RLS policy evaluation genuinely requires. But PostgREST exposes every
-- function in `public`, so it was also reachable as
-- POST /rest/v1/rpc/is_blocked_pair with arbitrary arguments — meaning anyone
-- could ask "is there a block between these two users?", and a blocked user
-- could ask about themselves and learn they had been blocked. That directly
-- defeats the property 0036 set out to have: the blocked party is never told.
--
-- Fix: move the predicate into a `private` schema. Policies can still call it
-- (they are fully qualified and the role has USAGE), but PostgREST only
-- exposes `public`, so it disappears from the API surface.

create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.is_blocked_pair(a uuid, b uuid)
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

revoke execute on function private.is_blocked_pair(uuid, uuid) from public, anon;
grant execute on function private.is_blocked_pair(uuid, uuid) to authenticated;

-- Repoint every dependent. The public function cannot be dropped until none
-- of these reference it.

drop policy if exists "profiles are readable by everyone" on public.profiles;
create policy "profiles are readable by everyone"
    on public.profiles for select to authenticated
    using (
        id = (select auth.uid())
        or not private.is_blocked_pair(id, (select auth.uid()))
    );

drop policy if exists "dreams are readable by everyone" on public.dreams;
create policy "dreams are readable by everyone"
    on public.dreams for select to authenticated
    using (not private.is_blocked_pair(owner_id, (select auth.uid())));

drop policy if exists "comments readable by signed-in users" on public.dream_comments;
create policy "comments readable by signed-in users"
    on public.dream_comments for select to authenticated
    using (
        not private.is_blocked_pair(user_id, (select auth.uid()))
        and exists (select 1 from public.dreams d where d.id = dream_comments.dream_id)
    );

drop policy if exists "users follow as themselves" on public.follows;
create policy "users follow as themselves"
    on public.follows for insert
    with check (
        (select auth.uid()) = follower_id
        and not private.is_blocked_pair(follower_id, followed_id)
    );

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
          and private.is_blocked_pair(cp.user_id, new.sender_id)
    ) then
        raise exception 'You can no longer message this person.'
            using errcode = '42501';
    end if;
    return new;
end;
$$;

revoke execute on function public.reject_blocked_message() from public, anon, authenticated;

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
    if v_owner is not null and private.is_blocked_pair(v_owner, new.user_id) then
        raise exception 'This content is unavailable.' using errcode = '42501';
    end if;
    return new;
end;
$$;

revoke execute on function public.reject_blocked_engagement() from public, anon, authenticated;
