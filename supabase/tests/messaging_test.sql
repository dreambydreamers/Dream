-- pgTAP tests for the messaging / help-offer security layer (migrations 0008-0011).
--
-- Self-contained: creates pgTAP + fixtures inside one transaction and ROLLBACKs,
-- so it leaves the database untouched. It impersonates real roles by switching
-- to the `authenticated` Postgres role and setting `request.jwt.claims.sub`,
-- which is exactly how RLS sees a signed-in user — so these assertions exercise
-- the real policies, not a superuser bypass.
--
-- Run via the Supabase MCP execute_sql tool (or psql). The final SELECT reports
-- pass/fail counts; `failures` must be 0.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_temp;

-- ---- Fixtures (as superuser) ----------------------------------------------
-- Inserting into auth.users fires handle_new_user(), which creates the profile.
insert into auth.users (id, email, aud, role) values
 ('11111111-1111-1111-1111-111111111111','owner@test.dev','authenticated','authenticated'),
 ('22222222-2222-2222-2222-222222222222','helper@test.dev','authenticated','authenticated'),
 ('33333333-3333-3333-3333-333333333333','stranger@test.dev','authenticated','authenticated');
insert into dreams (id, owner_id, title, category)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','Test Dream','tech');

create temp table _tap(line text);
grant insert on _tap to authenticated;   -- assertions run as the authenticated role
select plan(14);

-- ---- Helper (user 2) makes an offer on the owner's (user 1) dream ----------
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
create temp table _ids  as select * from create_help_offer('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Funding','I can help');
create temp table _ids2 as select * from create_help_offer('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Funding','dup');

insert into _tap select is((select already_existed from _ids), false, 'first offer is newly created');
insert into _tap select is((select already_existed from _ids2), true, 'duplicate tap returns the existing offer');
insert into _tap select is((select count(*)::int from help_offers where dream_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 1, 'no duplicate offer rows (dedupe)');
insert into _tap select is((select count(*)::int from conversations c join _ids i on c.id=i.conversation_id), 1, 'helper can read their own conversation');
insert into _tap select cmp_ok((select count(*)::int from messages m join _ids i on m.conversation_id=i.conversation_id), '>=', 1, 'helper sees the system message');

-- ---- Owner (user 1) cannot offer help on their own dream -------------------
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
insert into _tap select throws_ok($$ select create_help_offer('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Funding','x') $$, '42501', 'You cannot offer help on your own dream', 'owner cannot offer on own dream');
insert into _tap select is((select count(*)::int from notifications where type='offer_received'), 1, 'owner sees the offer_received notification');

-- ---- Stranger (user 3) is fully locked out --------------------------------
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', true);
insert into _tap select throws_ok($$ select respond_to_help_offer((select offer_id from _ids), 'accepted') $$, '42501', 'Only the dream owner can respond to this offer', 'non-owner cannot respond to an offer');
insert into _tap select is((select count(*)::int from messages m join _ids i on m.conversation_id=i.conversation_id), 0, 'non-participant cannot read messages');
insert into _tap select is((select count(*)::int from conversations c join _ids i on c.id=i.conversation_id), 0, 'non-participant cannot read the conversation');
insert into _tap select is((select count(*)::int from notifications), 0, 'a user only ever sees their own notifications');

-- ---- Owner accepts; helper is notified and the status flips ----------------
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
insert into _tap select lives_ok($$ select respond_to_help_offer((select offer_id from _ids),'accepted') $$, 'owner can accept the offer');

select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
insert into _tap select is((select count(*)::int from notifications where type='offer_accepted'), 1, 'helper is notified of acceptance');
insert into _tap select is((select status::text from help_offers where id=(select offer_id from _ids)), 'accepted', 'offer status becomes accepted');

-- ---- Report ----------------------------------------------------------------
reset role;
select
  count(*) filter (where line like 'ok %')    as passes,
  count(*) filter (where line like 'not ok%') as failures,
  coalesce(string_agg(line, ' | ') filter (where line like 'not ok%'), 'none') as failure_lines
from _tap;
rollback;
