-- 0037_blocked_profiles_rpc.sql
-- Follow-up to 0036: let a user manage the list of people they blocked.
--
-- 0036's profiles policy hides a blocked user from the blocker as well as the
-- other way round — that symmetry is the point of a block. It also means the
-- "Blocked accounts" screen cannot resolve names through the normal profiles
-- read, and would render a list of bare UUIDs with no way to tell who is who.
--
-- This RPC is the one deliberate hole: it returns display fields for exactly
-- the people the CALLER has blocked, and nothing else. It never reveals who
-- blocked the caller.

create or replace function public.list_blocked_profiles()
returns table (
    id uuid,
    name text,
    handle text,
    avatar_seed int,
    avatar_url text,
    blocked_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select p.id, p.name, p.handle, p.avatar_seed, p.avatar_url, b.created_at
    from public.user_blocks b
    join public.profiles p on p.id = b.blocked_id
    where b.blocker_id = auth.uid()
    order by b.created_at desc
    limit 200;
$$;

revoke execute on function public.list_blocked_profiles() from public, anon;
grant execute on function public.list_blocked_profiles() to authenticated;
