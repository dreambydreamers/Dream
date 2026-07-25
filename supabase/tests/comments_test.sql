-- pgTAP tests for dream comments (migration 0025): RLS, counts view, and the
-- owner notification trigger. Transactional + ROLLBACK — safe on any project.
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

insert into dreams (id, owner_id, title, category)
values ('ccccccc1-0000-0000-0000-000000000001','77777777-7777-7777-7777-777777777777','Comment test dream','tech');

create temp table _tap(line text);
grant insert on _tap to authenticated;
select plan(10);

-- ---- Commenter posts -------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}', true);

insert into dream_comments (id, dream_id, user_id, body)
values ('ddddddd1-0000-0000-0000-000000000001','ccccccc1-0000-0000-0000-000000000001','66666666-6666-6666-6666-666666666666','You should talk to the folks at TechHub!');

insert into _tap select is((select count(*)::int from dream_comments where dream_id='ccccccc1-0000-0000-0000-000000000001'), 1, 'comment is inserted and readable');
insert into _tap select is((select comments_count::int from dream_comment_counts where dream_id='ccccccc1-0000-0000-0000-000000000001'), 1, 'count view reflects the comment');
insert into _tap select throws_ok($$ insert into dream_comments (dream_id, user_id, body) values ('ccccccc1-0000-0000-0000-000000000001','77777777-7777-7777-7777-777777777777','impersonated') $$, '42501', null, 'cannot insert a comment as someone else');
insert into _tap select throws_ok($$ insert into dream_comments (dream_id, user_id, body) values ('ccccccc1-0000-0000-0000-000000000001','66666666-6666-6666-6666-666666666666','   ') $$, '23514', null, 'blank comment body is rejected');

-- ---- Owner is notified; self-comments are not ------------------------------
select set_config('request.jwt.claims','{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}', true);
insert into _tap select is((select count(*)::int from notifications where type='comment' and user_id='77777777-7777-7777-7777-777777777777'), 1, 'dream owner receives a comment notification');

insert into dream_comments (dream_id, user_id, body)
values ('ccccccc1-0000-0000-0000-000000000001','77777777-7777-7777-7777-777777777777','Thanks!');
insert into _tap select is((select count(*)::int from notifications where type='comment' and user_id='77777777-7777-7777-7777-777777777777'), 1, 'self-comments do not notify');

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
insert into _tap select is((select comments_count from dream_comment_counts where dream_id='ccccccc1-0000-0000-0000-000000000001'), 1::bigint, 'count view tracks deletions (owner''s own reply remains)');

-- ---- Report ----------------------------------------------------------------
reset role;
select
  count(*) filter (where line like 'ok %')    as passes,
  count(*) filter (where line like 'not ok%') as failures,
  coalesce(string_agg(line, ' | ') filter (where line like 'not ok%'), 'none') as failure_lines
from _tap;
rollback;
