-- pgTAP tests for blocking, reporting and rate limiting (migrations 0035-0037).
--
-- Self-contained: fixtures inside one transaction, ROLLBACK at the end, so it
-- leaves the database untouched. Impersonates signed-in users by switching to
-- the `authenticated` role with `request.jwt.claims.sub`, exercising the real
-- RLS policies rather than a superuser bypass.
--
-- Run via the Supabase MCP execute_sql tool (or psql). The final SELECT
-- reports pass/fail counts; `failures` must be 0.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_temp;

-- ---- Fixtures (as superuser) ----------------------------------------------
insert into auth.users (id, email, aud, role) values
 ('a1111111-1111-1111-1111-111111111111','abuser@test.dev','authenticated','authenticated'),
 ('b2222222-2222-2222-2222-222222222222','victim@test.dev','authenticated','authenticated'),
 ('c3333333-3333-3333-3333-333333333333','bystander@test.dev','authenticated','authenticated');

insert into dreams (id, owner_id, title, category) values
 ('d1111111-0000-0000-0000-000000000001','a1111111-1111-1111-1111-111111111111','Abuser dream','tech'),
 ('d2222222-0000-0000-0000-000000000002','b2222222-2222-2222-2222-222222222222','Victim dream','art');
insert into dream_videos (id, dream_id, storage_path, is_primary) values
 ('e1111111-0000-0000-0000-000000000001','d1111111-0000-0000-0000-000000000001','t/a.mp4',true);
insert into dream_comments (id, dream_id, user_id, body) values
 ('cc111111-0000-0000-0000-000000000001','d2222222-0000-0000-0000-000000000002',
  'a1111111-1111-1111-1111-111111111111','nasty comment');
insert into follows (follower_id, followed_id) values
 ('a1111111-1111-1111-1111-111111111111','b2222222-2222-2222-2222-222222222222');

create temp table _tap(line text);
grant insert on _tap to authenticated;
select plan(19);

-- ---- Baseline: everything visible before the block -------------------------
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b2222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
insert into _tap select is((select count(*)::int from dreams where id='d1111111-0000-0000-0000-000000000001'), 1,
    'before block: abuser dream is visible');
insert into _tap select is((select count(*)::int from dream_comments where id='cc111111-0000-0000-0000-000000000001'), 1,
    'before block: abuser comment is visible');

-- ---- The victim blocks the abuser ------------------------------------------
select block_user('a1111111-1111-1111-1111-111111111111');

insert into _tap select is((select count(*)::int from dreams where id='d1111111-0000-0000-0000-000000000001'), 0,
    'after block: abuser dream hidden from victim');
insert into _tap select is((select count(*)::int from dream_videos where id='e1111111-0000-0000-0000-000000000001'), 0,
    'after block: abuser video hidden — media inherits its dream''s visibility');
insert into _tap select is((select count(*)::int from dream_comments where id='cc111111-0000-0000-0000-000000000001'), 0,
    'after block: abuser comment hidden from victim');
insert into _tap select is((select count(*)::int from profiles where id='a1111111-1111-1111-1111-111111111111'), 0,
    'after block: abuser profile hidden from victim');
insert into _tap select is((select count(*)::int from follows where follower_id='a1111111-1111-1111-1111-111111111111'), 0,
    'block_user drops the existing follow edge');
insert into _tap select is((select count(*)::int from search_dreams('Abuser')), 0,
    'search_dreams (SECURITY DEFINER, bypasses RLS) still excludes a blocked owner');
insert into _tap select is((select count(*)::int from user_blocks), 1,
    'blocker sees their own block row');
insert into _tap select is((select count(*)::int from list_blocked_profiles()), 1,
    'blocked-accounts screen can still resolve the blocked profile');

-- ---- The block is symmetric ------------------------------------------------
select set_config('request.jwt.claims','{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
insert into _tap select is((select count(*)::int from dreams where id='d2222222-0000-0000-0000-000000000002'), 0,
    'symmetric: victim dream hidden from the blocked user too');
insert into _tap select is((select count(*)::int from user_blocks), 0,
    'the blocked party is never told they were blocked');
insert into _tap select throws_ok(
  $$ insert into dream_comments (dream_id, user_id, body)
     values ('d2222222-0000-0000-0000-000000000002','a1111111-1111-1111-1111-111111111111','more abuse') $$,
  '42501', null, 'blocked user cannot comment on the blocker''s dream');
insert into _tap select throws_ok(
  $$ insert into dream_likes (dream_id, user_id)
     values ('d2222222-0000-0000-0000-000000000002','a1111111-1111-1111-1111-111111111111') $$,
  '42501', null, 'blocked user cannot like the blocker''s dream');
insert into _tap select throws_ok(
  $$ select share_dream_video('b2222222-2222-2222-2222-222222222222',
                              'd1111111-0000-0000-0000-000000000001', null, 'hi') $$,
  '42501', null, 'blocked user cannot open a DM via share_dream_video');
insert into _tap select throws_ok(
  $$ select create_help_offer('d2222222-0000-0000-0000-000000000002','Funding','hi') $$,
  '42501', null, 'blocked user cannot reach the blocker through a help offer');
insert into _tap select throws_ok(
  $$ insert into follows (follower_id, followed_id)
     values ('a1111111-1111-1111-1111-111111111111','b2222222-2222-2222-2222-222222222222') $$,
  '42501', null, 'blocked user cannot re-follow the blocker');

-- ---- Reporting -------------------------------------------------------------
insert into content_reports (reporter_id, reported_user_id, target_type, target_id, reason, note)
values ('a1111111-1111-1111-1111-111111111111','b2222222-2222-2222-2222-222222222222',
        'dream','d2222222-0000-0000-0000-000000000002','spam','test report');
insert into _tap select throws_ok(
  $$ insert into content_reports (reporter_id, reported_user_id, target_type, target_id, reason)
     values ('a1111111-1111-1111-1111-111111111111','b2222222-2222-2222-2222-222222222222',
             'dream','d2222222-0000-0000-0000-000000000002','harassment') $$,
  '23505', null, 'one report per user per target (duplicate is rejected)');

-- ---- Bystanders are unaffected ---------------------------------------------
select set_config('request.jwt.claims','{"sub":"c3333333-3333-3333-3333-333333333333","role":"authenticated"}', true);
insert into _tap select is((select count(*)::int from dreams
    where id in ('d1111111-0000-0000-0000-000000000001','d2222222-0000-0000-0000-000000000002')), 2,
    'a block between two users is invisible to everyone else');

-- ---- Report ----------------------------------------------------------------
reset role;
select
  count(*) filter (where line like 'ok %')    as passes,
  count(*) filter (where line like 'not ok%') as failures,
  coalesce(string_agg(line, ' | ') filter (where line like 'not ok%'), 'none') as failure_lines
from _tap;
rollback;
