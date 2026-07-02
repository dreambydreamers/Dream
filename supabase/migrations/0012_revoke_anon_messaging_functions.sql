-- Supabase grants EXECUTE on new public functions directly to the `anon` and
-- `authenticated` roles (not only to PUBLIC), so 0011's `revoke ... from public`
-- left anon access in place. Revoke it explicitly so these SECURITY DEFINER
-- functions are not part of the anonymous API surface.

revoke execute on function create_help_offer(uuid, text, text) from anon;
revoke execute on function respond_to_help_offer(uuid, help_offer_status) from anon;
revoke execute on function cancel_help_offer(uuid) from anon;
revoke execute on function mark_conversation_read(uuid) from anon;
revoke execute on function mark_notifications_read(uuid[]) from anon;
revoke execute on function mark_all_notifications_read() from anon;

-- RLS helper: not a public API; signed-in users keep access for policy checks.
revoke execute on function is_conversation_participant(uuid, uuid) from anon;

-- Trigger function: never called via the API by anyone.
revoke execute on function on_message_insert() from anon, authenticated;
