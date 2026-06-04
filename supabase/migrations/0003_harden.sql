-- Security hardening based on advisor lints
-- Run after 0002_storage.sql

-- 1. dream_stats view: run with caller's permissions/RLS, not creator's (ERROR)
alter view dream_stats set (security_invoker = on);

-- 2. set_updated_at: pin search_path (WARN)
alter function set_updated_at() set search_path = '';

-- 3. handle_new_user is a trigger function, not meant to be called via RPC.
--    Revoke EXECUTE from API roles so it can't be invoked through /rpc.
--    EXECUTE is granted to PUBLIC by default, so revoke from PUBLIC (covers anon/authenticated).
revoke execute on function handle_new_user() from public;

-- 4. Public buckets don't need a broad SELECT policy for URL access.
--    Drop the listing-enabling policies; object URLs still resolve.
drop policy "anyone reads posters" on storage.objects;
drop policy "anyone reads avatars" on storage.objects;
