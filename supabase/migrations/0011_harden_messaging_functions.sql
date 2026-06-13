-- Security hardening for the messaging functions, mirroring 0003_harden.sql.
--
-- EXECUTE is granted to PUBLIC by default, which exposes every function in the
-- `public` schema as a PostgREST RPC (callable even by the `anon` role). We want:
--   * the user-facing RPCs callable only by signed-in users,
--   * the trigger + RLS-helper functions not callable via the API at all.

-- User-facing RPCs: signed-in only (they already re-derive auth.uid() and raise
-- on null, but revoking anon access removes them from the anonymous API surface).
revoke execute on function create_help_offer(uuid, text, text) from public;
revoke execute on function respond_to_help_offer(uuid, help_offer_status) from public;
revoke execute on function cancel_help_offer(uuid) from public;
revoke execute on function mark_conversation_read(uuid) from public;
revoke execute on function mark_notifications_read(uuid[]) from public;
revoke execute on function mark_all_notifications_read() from public;

-- Trigger function: never called directly.
revoke execute on function on_message_insert() from public;

-- RLS helper: referenced by the conversation/message policies, so it must stay
-- executable by signed-in users, but it should not be a public RPC.
revoke execute on function is_conversation_participant(uuid, uuid) from public;
grant execute on function is_conversation_participant(uuid, uuid) to authenticated;
