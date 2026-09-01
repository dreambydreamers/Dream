-- 0031_revoke_public_function_execute.sql
-- Production-readiness audit (2026-08): close anonymous RPC access.
--
-- Postgres grants EXECUTE on every new function to PUBLIC by default, and
-- PostgREST exposes anything in `public` at /rest/v1/rpc/<name>. Several
-- migrations added `grant execute ... to authenticated` without a matching
-- `revoke ... from public`, so the grant was decorative — the function was
-- already callable by `anon`.
--
-- The serious case is search: 0017 created search_dreams / search_profiles as
-- SECURITY DEFINER, so they bypass RLS entirely. Combined with the PUBLIC
-- grant, anyone holding the shipped publishable key could page out the whole
-- user directory (name, handle, location, avatar) and dream catalog without an
-- account — which silently defeated 0019, whose entire point was scoping those
-- reads to signed-in users.

-- =========================================================
-- 1. Search RPCs: authenticated only.
-- =========================================================

revoke execute on function public.search_dreams(text)  from public, anon;
revoke execute on function public.search_profiles(text) from public, anon;

grant execute on function public.search_dreams(text)  to authenticated;
grant execute on function public.search_profiles(text) to authenticated;

-- =========================================================
-- 2. Trigger functions are not an API.
-- =========================================================
-- Neither is meaningful outside a trigger context (they reference NEW), but a
-- SECURITY DEFINER function reachable by `anon` is not something to leave lying
-- around. Triggers execute as the table owner and ignore EXECUTE grants, so
-- revoking here does not affect them.

revoke execute on function public.handle_new_user()  from public, anon, authenticated;
revoke execute on function public.set_updated_at()   from public, anon, authenticated;

-- =========================================================
-- 3. Stop the default from reintroducing this.
-- =========================================================
-- Applies to functions created *later* by the same role. New RPCs must now opt
-- in with an explicit `grant execute ... to authenticated`, which is the
-- behaviour every migration here already assumed it had.

alter default privileges in schema public revoke execute on functions from public;
