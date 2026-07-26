-- pgTAP tests for dream comments (migrations 0025-0027): RLS, per-update
-- threads, clip-cascade deletion, the counts view, and the owner
-- notification trigger.
-- Transactional + ROLLBACK — safe on any project.
-- Run via the Supabase MCP execute_sql tool (or psql); `failures` must be 0.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_temp;

-- ---- Fixtures (as superuser) ----------------------------------------------
insert into auth.users (id, email, aud, role) values
 ('66666666-6666-6666-6666-666666666666','commenter@test.dev','authenticated','authenticated'),
 ('77777777-7777-7777-7777-777777777777','dream-owner@test.dev','authenticated','authenticated'),
 ('88888888-8888-8888-8888-888888888888','stranger@test.dev','authenticated','authenticated')
on conflict (id) do nothing;

-- Dream without videos (dream-level thread) …
insert into dreams (id, owner_id, title, category)
values ('ccccccc1-0000-0000-0000-000000000001','77777777-7777-7777-7777-777777777777','Comment test dream','tech');

-- … and a dream with a cover + an update clip (per-clip threads).
insert into dreams (id, owner_id, title, category)
values ('ccccccc2-0000-0000-0000-000000000002','77777777-7777-7777-7777-777777777777','Two-clip dream','art');
insert into dream_videos (id, dream_id, storage_path, is_primary, created_at) values
 ('cccccc11-0000-0000-0000-000000000011','ccccccc2-0000-0000-0000-000000000002','t/cover.mp4', true,  now() - interval '10 days'),
 ('cccccc12-0000-0000-0000-000000000012','ccccccc2-0000-0000-0000-000000000002','t/update.mp4', false, now() - interval '1 day');

create temp table _tap(line text);
grant insert on _tap to authenticated;
select plan(16);

-- ---- Commenter posts on the videoless dream --------------------------------
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}', true);

insert into dream_comments (id, dream_id, user_id, body)
values ('ddddddd1-0000-0000-0000-000000000001','ccccccc1-0000-0000-0000-000000000001','66666666-6666-6666-6666-666666666666','You should talk to the folks at TechHub!');

insert into _tap select is((select count(*)::int from dream_comments where dream_id='ccccccc1-0000-0000-0000-000000000001'), 1, 'comment is inserted and readable');
insert into _tap select is((select comments_count::int from dream_comment_counts where thread_id='ccccccc1-0000-0000-0000-000000000001'), 1, 'videoless dream: thread keys on the dream id');
insert into _tap select throws_ok($$ insert into dream_comments (dream_id, user_id, body) values ('ccccccc1-0000-0000-0000-000000000001','77777777-7777-7777-7777-777777777777','impersonated') $$, '42501', null, 'cannot insert a comment as someone else');
insert into _tap select throws_ok($$ insert into dream_comments (dream_id, user_id, body) values ('ccccccc1-0000-0000-0000-000000000001','66666666-6666-6666-6666-666666666666','   ') $$, '23514', null, 'blank comment body is rejected');

-- ---- Per-update threads: each clip owns its own comment section -------------
insert into dream_comments (dream_id, video_id, user_id, body)
values ('ccccccc2-0000-0000-0000-000000000002','cccccc11-0000-0000-0000-000000000011','66666666-6666-6666-6666-666666666666','Cover thread comment');

insert into _tap select is((select count(*)::int from dream_comments where dream_id='ccccccc2-0000-0000-0000-000000000002' and video_id='cccccc12-0000-0000-0000-000000000012'), 0,
    'update clip thread is empty — cover comment does not leak into it');
insert into _tap select is((select comments_count::int from dream_comment_counts where thread_id='cccccc11-0000-0000-0000-000000000011'), 1,
    'cover thread counts its own comment');

insert into dream_comments (dream_id, video_id, user_id, body)
values ('ccccccc2-0000-0000-0000-000000000002','cccccc12-0000-0000-0000-000000000012','66666666-6666-6666-6666-666666666666','Update thread comment');

insert into _tap select is((select count(*)::int from dream_comment_counts where dream_id='ccccccc2-0000-0000-0000-000000000002'), 2,
    'two clips with comments = two separate count rows');
insert into _tap select is((select count(*)::int from dream_comments where dream_id='ccccccc2-0000-0000-0000-000000000002' and video_id='cccccc11-0000-0000-0000-000000000011'), 1,
    'cover thread still has exactly its own comment after posting to the update');

-- ---- Owner is notified; self-comments are not ------------------------------
select set_config('request.jwt.claims','{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}', true);
insert into _tap select is((select count(*)::int from notifications where type='comment' and user_id='77777777-7777-7777-7777-777777777777'), 3, 'dream owner receives comment notifications');

insert into dream_comments (dream_id, user_id, body)
values ('ccccccc1-0000-0000-0000-000000000001','77777777-7777-7777-7777-777777777777','Thanks!');
insert into _tap select is((select count(*)::int from notifications where type='comment' and user_id='77777777-7777-7777-7777-777777777777'), 3, 'self-comments do not notify');

-- ---- Stranger cannot delete ------------------------------------------------
select set_config('request.jwt.claims','{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated"}', true);
delete from dream_comments where id='ddddddd1-0000-0000-0000-000000000001';
insert into _tap select is((select count(*)::int from dream_comments where id='ddddddd1-0000-0000-0000-000000000001'), 1, 'stranger cannot delete someone else''s comment');

-- ---- Author deletes own ----------------------------------------------------
select set_config('request.jwt.claims','{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}', true);
delete from dream_comments where id='ddddddd1-0000-0000-0000-000000000001';
insert into _tap select is((select count(*)::int from dream_comments where id='ddddddd1-0000-0000-0000-000000000001'), 0, 'author deletes their own comment');

-- ---- Dream owner moderates -------------------------------------------------
select set_config('request.jwt.claims','{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}', true);
insert into dream_comments (id, dream_id, user_id, body)
values ('ddddddd2-0000-0000-0000-000000000002','ccccccc1-0000-0000-0000-000000000001','66666666-6666-6666-6666-666666666666','spam spam spam');

select set_config('request.jwt.claims','{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}', true);
delete from dream_comments where id='ddddddd2-0000-0000-0000-000000000002';
insert into _tap select is((select count(*)::int from dream_comments where id='ddddddd2-0000-0000-0000-000000000002'), 0, 'dream owner can delete comments on their dream');
insert into _tap select is((select comments_count from dream_comment_counts where thread_id='ccccccc1-0000-0000-0000-000000000001'), 1::bigint, 'count view tracks deletions (owner''s own reply remains)');

-- ---- Deleting a clip cascade-deletes its thread ----------------------------
reset role;
delete from dream_videos where id='cccccc12-0000-0000-0000-000000000012';

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}', true);
insert into _tap select is((select count(*)::int from dream_comments where dream_id='ccccccc2-0000-0000-0000-000000000002' and video_id is null), 0,
    'deleted clip''s comments are gone, not orphaned onto the dream-level thread');
insert into _tap select is((select count(*)::int from dream_comments where dream_id='ccccccc2-0000-0000-0000-000000000002'), 1,
    'the surviving clip''s thread is untouched by the deletion');

-- ---- Report ----------------------------------------------------------------
reset role;
select
  count(*) filter (where line like 'ok %')    as passes,
  count(*) filter (where line like 'not ok%') as failures,
  coalesce(string_agg(line, ' | ') filter (where line like 'not ok%'), 'none') as failure_lines
from _tap;
rollback;
