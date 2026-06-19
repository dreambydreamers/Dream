-- 0015 replaces on_message_insert(), which resets default EXECUTE grants.
-- Keep it trigger-only and unavailable through /rpc.

revoke execute on function on_message_insert() from public;
revoke execute on function on_message_insert() from anon;
revoke execute on function on_message_insert() from authenticated;
