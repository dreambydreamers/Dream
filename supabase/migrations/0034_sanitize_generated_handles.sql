-- 0034_sanitize_generated_handles.sql
-- Follow-up to 0032: make handle generation satisfy the handle format check.
--
-- 0032 added `profiles_handle_format`. Running the comments pgTAP suite against
-- it surfaced a sign-up-breaking interaction: handle_new_user() took the handle
-- straight from sign-up metadata, falling back to the email local-part, with no
-- sanitization. A local-part containing '-' (dream-owner@…), a '+' tag, a
-- 40-character address, or a user-typed handle with spaces or emoji would all
-- fail the new CHECK — and because that insert happens inside the
-- on_auth_user_created trigger, the failure aborts the enclosing auth.users
-- insert. The user could not create an account at all.
--
-- Two changes, so the constraint can never be the thing that blocks a sign-up:
--   1. Allow '-' in handles (common, and what the email fallback produces).
--   2. Sanitize inside the trigger, and fall back to a null handle — which the
--      function already treats as valid — whenever nothing usable survives.
--      A null handle renders as "anon" in the app until the user sets one.

-- =========================================================
-- 1. Hyphens are legal in a handle.
-- =========================================================

alter table public.profiles
    drop constraint if exists profiles_handle_format;
alter table public.profiles
    add constraint profiles_handle_format
    check (handle is null or handle ~ '^[a-zA-Z0-9_.-]{2,30}$');

-- =========================================================
-- 2. Generate handles that always satisfy it.
-- =========================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    meta_name   text := nullif(trim(new.raw_user_meta_data ->> 'name'), '');
    meta_handle text := nullif(trim(new.raw_user_meta_data ->> 'handle'), '');
    fallback    text := nullif(split_part(coalesce(new.email, ''), '@', 1), '');
    want_handle text := coalesce(meta_handle, fallback);
begin
    -- Drop every character the format check rejects, then clamp the length.
    -- left() on a shorter string is a no-op, so this only ever truncates.
    want_handle := left(regexp_replace(coalesce(want_handle, ''), '[^a-zA-Z0-9_.-]', '', 'g'), 30);

    -- Too short to be a handle (or nothing survived sanitizing) → no handle.
    if char_length(want_handle) < 2 then
        want_handle := null;
    end if;

    -- Unchanged from the original: a taken handle becomes null rather than
    -- failing the insert; the user picks a new one in Edit Profile.
    if want_handle is not null
       and exists (select 1 from public.profiles where handle = want_handle) then
        want_handle := null;
    end if;

    insert into public.profiles (id, name, handle)
    values (new.id, left(meta_name, 80), want_handle)
    on conflict (id) do nothing;
    return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
