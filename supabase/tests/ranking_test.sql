-- pgTAP tests for the recommendation layer (migrations 0021-0024):
-- candidate generation exclusions, source tagging, engagement ingestion, and
-- the viewer-isolation guarantees.
--
-- Self-contained: fixtures inside one transaction, ROLLBACK at the end, so it
-- leaves the database untouched. Impersonates signed-in users by switching to
-- the `authenticated` role with `request.jwt.claims.sub`, exercising the real
-- RLS policies and SECURITY INVOKER functions.
--
-- Run via the Supabase MCP execute_sql tool (or psql). The final SELECT
-- reports pass/fail counts; `failures` must be 0.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_temp;

-- ---- Fixtures (as superuser) ----------------------------------------------
-- viewer: offers funding only. owner: owns all test dreams.
insert into auth.users (id, email, aud, role) values
 ('44444444-4444-4444-4444-444444444444','rank-viewer@test.dev','authenticated','authenticated'),
 ('55555555-5555-5555-5555-555555555555','rank-owner@test.dev','authenticated','authenticated')
on conflict (id) do nothing;

insert into supporter_profiles (user_id, help_types)
values ('44444444-4444-4444-4444-444444444444', array['funding']::help_type[]);

-- Dreams (created_at 10 days ago so the 'fresh' source can't admit them):
--   b1: needs code only  -> help-type MISMATCH for the viewer
--   b2: needs funding    -> help-type MATCH
--   b3: owned by viewer  -> must never appear
--   b4: dismissed        -> must never appear
--   b5: seen recently    -> must not appear within TTL
--   b6: needs funding, zero exposure -> underexposed source
insert into dreams (id, owner_id, title, category, stage, help_tags, created_at) values
 ('bbbbbbb1-0000-0000-0000-000000000001','55555555-5555-5555-5555-555555555555','Code dream','tech','early',array['Coding'], now() - interval '10 days'),
 ('bbbbbbb2-0000-0000-0000-000000000002','55555555-5555-5555-5555-555555555555','Funding dream','food','early',array['Funding'], now() - interval '10 days'),
 ('bbbbbbb3-0000-0000-0000-000000000003','44444444-4444-4444-4444-444444444444','Own dream','art','early',array['Funding'], now() - interval '10 days'),
 ('bbbbbbb4-0000-0000-0000-000000000004','55555555-5555-5555-5555-555555555555','Dismissed dream','music','early',array['Funding'], now() - interval '10 days'),
 ('bbbbbbb5-0000-0000-0000-000000000005','55555555-5555-5555-5555-555555555555','Seen dream','sport','early',array['Funding'], now() - interval '10 days'),
 ('bbbbbbb6-0000-0000-0000-000000000006','55555555-5555-5555-5555-555555555555','Starved funding dream','health','early',array['Funding'], now() - interval '10 days');

-- Exposure: b1/b2/b4/b5 are ABOVE the underexposed floor (25); b6 stays at 0.
update dream_exposure_counters set distinct_viewers = 40, impressions = 200
where dream_id in ('bbbbbbb1-0000-0000-0000-000000000001',
                   'bbbbbbb2-0000-0000-0000-000000000002',
                   'bbbbbbb4-0000-0000-0000-000000000004',
                   'bbbbbbb5-0000-0000-0000-000000000005');

-- Viewer already dismissed b4 and saw b5 yesterday.
insert into dream_seen (user_id, dream_id, first_seen_at, last_seen_at, dismissed) values
 ('44444444-4444-4444-4444-444444444444','bbbbbbb4-0000-0000-0000-000000000004', now() - interval '20 days', now() - interval '20 days', true),
 ('44444444-4444-4444-4444-444444444444','bbbbbbb5-0000-0000-0000-000000000005', now() - interval '1 day', now() - interval '1 day', false);

create temp table _tap(line text);
grant insert on _tap to authenticated;
select plan(15);

-- ---- Candidate generation as the viewer ------------------------------------
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}', true);

create temp table _cands as select * from get_feed_candidates();

insert into _tap select is((select count(*)::int from _cands where dream_id='bbbbbbb1-0000-0000-0000-000000000001'), 0,
    'help-type mismatch (code-only dream, funding-only viewer) is excluded entirely');
insert into _tap select is((select count(*)::int from _cands where dream_id='bbbbbbb2-0000-0000-0000-000000000002'), 1,
    'help-type match is a candidate');
insert into _tap select ok((select 'help_type_match' = any(sources) from _cands where dream_id='bbbbbbb2-0000-0000-0000-000000000002'),
    'matching dream carries the help_type_match source');
insert into _tap select is((select count(*)::int from _cands where dream_id='bbbbbbb3-0000-0000-0000-000000000003'), 0,
    'own dreams are excluded');
insert into _tap select is((select count(*)::int from _cands where dream_id='bbbbbbb4-0000-0000-0000-000000000004'), 0,
    'dismissed dreams are excluded');
insert into _tap select is((select count(*)::int from _cands where dream_id='bbbbbbb5-0000-0000-0000-000000000005'), 0,
    'recently-seen dreams are excluded within the TTL');
insert into _tap select ok((select 'underexposed' = any(sources) from _cands where dream_id='bbbbbbb6-0000-0000-0000-000000000006'),
    'zero-exposure compatible dream carries the underexposed source');
insert into _tap select ok((select distinct_viewers < 25 from _cands where dream_id='bbbbbbb6-0000-0000-0000-000000000006'),
    'underexposed candidate reports its exposure deficit');

-- ---- Viewer ranking profile -------------------------------------------------
insert into _tap select ok((select 'funding' = any(help_types) from get_viewer_ranking_profile()),
    'viewer profile returns declared help types');

-- ---- Engagement ingestion: view maintains seen-set + counters ---------------
select log_engagement_batch(jsonb_build_array(
    jsonb_build_object('dream_id','bbbbbbb2-0000-0000-0000-000000000002','event_type','view')));
select log_engagement_batch(jsonb_build_array(
    jsonb_build_object('dream_id','bbbbbbb2-0000-0000-0000-000000000002','event_type','view')));

insert into _tap select is((select seen_count from dream_seen where user_id='44444444-4444-4444-4444-444444444444' and dream_id='bbbbbbb2-0000-0000-0000-000000000002'), 2,
    'repeat views bump seen_count');
insert into _tap select is((select impressions::int from dream_exposure_counters where dream_id='bbbbbbb2-0000-0000-0000-000000000002'), 202,
    'each view adds one impression');
insert into _tap select is((select distinct_viewers::int from dream_exposure_counters where dream_id='bbbbbbb2-0000-0000-0000-000000000002'), 41,
    'repeat views by the same viewer add only ONE distinct viewer');

-- Skips are log-only: no global counter moves at all.
select log_engagement_batch(jsonb_build_array(
    jsonb_build_object('dream_id','bbbbbbb6-0000-0000-0000-000000000006','event_type','skip','watch_ms',900,'video_duration_ms',20000),
    jsonb_build_object('dream_id','bbbbbbb6-0000-0000-0000-000000000006','event_type','skip','watch_ms',700,'video_duration_ms',20000)));
insert into _tap select is((select impressions::int from dream_exposure_counters where dream_id='bbbbbbb6-0000-0000-0000-000000000006'), 0,
    'skips do not touch impressions');
insert into _tap select is((select distinct_viewers::int from dream_exposure_counters where dream_id='bbbbbbb6-0000-0000-0000-000000000006'), 0,
    'skips do not touch distinct viewers');

-- not_relevant dismisses: the dream disappears from the next candidate fetch.
select log_engagement_batch(jsonb_build_array(
    jsonb_build_object('dream_id','bbbbbbb6-0000-0000-0000-000000000006','event_type','not_relevant')));
insert into _tap select is((select count(*)::int from get_feed_candidates() where dream_id='bbbbbbb6-0000-0000-0000-000000000006'), 0,
    'not_relevant dismisses the dream from future candidates');

-- ---- Report ----------------------------------------------------------------
reset role;
select
  count(*) filter (where line like 'ok %')    as passes,
  count(*) filter (where line like 'not ok%') as failures,
  coalesce(string_agg(line, ' | ') filter (where line like 'not ok%'), 'none') as failure_lines
from _tap;
rollback;
