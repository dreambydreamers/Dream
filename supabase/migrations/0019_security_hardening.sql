-- 0019_security_hardening.sql
-- Security hardening from the 2026-07 codebase audit.

-- =========================================================
-- 1. help_offers: remove the direct UPDATE policy.
-- =========================================================
-- The policy let a supporter PATCH their own row (e.g. status = 'accepted' /
-- 'completed'), bypassing the owner-only respond_to_help_offer RPC and
-- corrupting offer counts. Every legitimate lifecycle change goes through the
-- SECURITY DEFINER RPCs (0010/0018), which bypass RLS — so no direct UPDATE
-- policy is needed at all.

drop policy "supporter updates own offer; owner updates status" on help_offers;

-- =========================================================
-- 2. Scope catalog reads to signed-in users.
-- =========================================================
-- These SELECT policies applied to `public` (anon included), letting anyone
-- holding the shipped publishable key scrape the full user directory and
-- dream catalog without an account. The app always operates signed-in.

alter policy "profiles are readable by everyone"      on profiles      to authenticated;
alter policy "dreams are readable by everyone"        on dreams        to authenticated;
alter policy "journey steps are readable by everyone" on journey_steps to authenticated;
alter policy "dream videos are readable by everyone"  on dream_videos  to authenticated;
alter policy "supporters are readable by everyone"    on supporters    to authenticated;
alter policy "follows are readable by everyone"       on follows       to authenticated;

-- =========================================================
-- 3. messages: direct inserts may only be plain text.
-- =========================================================
-- 'system' and 'dream_share' rows are minted exclusively by the SECURITY
-- DEFINER RPCs (which bypass RLS); without this check a participant could
-- forge official-looking system lines or share cards in their threads.

drop policy "participants send messages" on messages;
create policy "participants send messages"
    on messages for insert
    with check (
        sender_id = auth.uid()
        and is_conversation_participant(conversation_id, auth.uid())
        and kind = 'text'
    );

-- =========================================================
-- 4. profiles: explicit WITH CHECK on UPDATE.
-- =========================================================
-- Postgres already reuses USING as the check; made explicit for consistency
-- with the notifications policy (0009).

alter policy "users can update their own profile"
    on profiles
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- =========================================================
-- 5. Realtime Authorization for chat typing/presence channels.
-- =========================================================
-- Broadcast and Presence do NOT go through table RLS — they require policies
-- on realtime.messages plus a private channel client-side (ChatRepository sets
-- isPrivate = true). Without this, any authenticated user who learned a
-- conversation UUID could join `conversation:<uuid>`, watch presence, and
-- spoof typing events. The regex guard keeps the uuid cast from throwing on
-- malformed topics; uuidString from Swift is uppercase, so match
-- case-insensitively.

create policy "participants receive conversation channel events"
    on realtime.messages for select
    to authenticated
    using (
        realtime.topic() ~* '^conversation:[0-9a-f-]{36}$'
        and public.is_conversation_participant(
                split_part(realtime.topic(), ':', 2)::uuid,
                auth.uid())
    );

create policy "participants send conversation channel events"
    on realtime.messages for insert
    to authenticated
    with check (
        realtime.topic() ~* '^conversation:[0-9a-f-]{36}$'
        and public.is_conversation_participant(
                split_part(realtime.topic(), ':', 2)::uuid,
                auth.uid())
    );
