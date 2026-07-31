-- Candidate generation for the recommendation feed.
--
-- Division of labor: SQL produces ~300 raw candidates from independent
-- sources (each a CTE below — this is the seam where an embedding-based
-- source gets added later) with exposure counters attached. ALL scoring,
-- fairness slotting, and diversity re-ranking happen in the pure Swift
-- ranker (Packages/DreamRanking) — never here.
--
-- Both functions are SECURITY INVOKER: every input table is readable under
-- RLS by the signed-in viewer (own profile/events/seen rows, public dreams,
-- counters).

-- One row describing the viewer for the ranker: capabilities, declared
-- interests, follow graph, and a learned category affinity built ONLY from
-- the viewer's own last-30d engagement (watch signals adjust the viewer's
-- profile — they never touch a dream's global standing).
create or replace function public.get_viewer_ranking_profile()
returns table (
    user_id uuid,
    skills text[],
    location text,
    help_types public.help_type[],
    weekly_capacity_hours int,
    categories_of_interest public.dream_category[],
    preferred_stages public.dream_stage[],
    followed_owner_ids uuid[],
    category_affinity jsonb
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
with me as (
    select p.id, p.skills, p.location
    from public.profiles p
    where p.id = (select auth.uid())
),
sp as (
    select s.help_types, s.weekly_capacity_hours, s.categories_of_interest, s.preferred_stages
    from public.supporter_profiles s
    where s.user_id = (select auth.uid())
),
fo as (
    select coalesce(array_agg(f.followed_id), '{}'::uuid[]) as ids
    from public.follows f
    where f.follower_id = (select auth.uid())
),
raw_aff as (
    select d.category::text as cat,
        sum(case e.event_type
            when 'complete'       then 1.0
            when 'watch_progress' then coalesce(e.completion_ratio, 0.3)
            when 'save'           then 1.5
            when 'share'          then 1.5
            when 'offer_help'     then 1.5
            when 'follow'         then 1.0
            when 'skip'           then -0.3
            when 'not_relevant'   then -1.0
            else 0.0
        end) as pts
    from public.engagement_events e
    join public.dreams d on d.id = e.dream_id
    where e.user_id = (select auth.uid())
      and e.created_at > now() - interval '30 days'
    group by d.category
),
aff as (
    select coalesce(
        jsonb_object_agg(x.cat, round(greatest(x.pts, 0) / nullif(x.max_pts, 0), 3)),
        '{}'::jsonb) as j
    from (select cat, pts, max(pts) over () as max_pts from raw_aff) x
    where x.max_pts > 0
)
select
    me.id,
    coalesce(me.skills, '{}'::text[]),
    me.location,
    coalesce(sp.help_types, '{}'::public.help_type[]),
    coalesce(sp.weekly_capacity_hours, 2),
    coalesce(sp.categories_of_interest, '{}'::public.dream_category[]),
    coalesce(sp.preferred_stages, '{}'::public.dream_stage[]),
    fo.ids,
    coalesce((select j from aff), '{}'::jsonb)
from me
left join sp on true
cross join fo
$$;

revoke execute on function public.get_viewer_ranking_profile() from public, anon;
grant execute on function public.get_viewer_ranking_profile() to authenticated;

-- Multi-source candidate pool. Every source applies the same exclusions
-- (own dreams, dismissed, seen within TTL); the 'underexposed' source is the
-- server half of the fairness pass — it surfaces dreams below the viewer
-- floor so the ranker can inject them into reserved slots regardless of
-- their quality score.
create or replace function public.get_feed_candidates(
    p_limit int default 300,
    p_seen_ttl_days int default 14,
    p_underexposed_viewer_floor int default 25
)
returns table (
    dream_id uuid,
    owner_id uuid,
    title text,
    category public.dream_category,
    stage public.dream_stage,
    location text,
    help_tags text[],
    help_types public.help_type[],
    created_at timestamptz,
    offers_count bigint,
    supporters_count bigint,
    impressions bigint,
    distinct_viewers bigint,
    is_followed_owner boolean,
    has_video boolean,
    sources text[]
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
with viewer as (
    select
        p.id as user_id,
        (select array_agg(lower(trim(s))) from unnest(p.skills) as s) as skills,
        nullif(lower(trim(coalesce(p.location, ''))), '') as loc,
        coalesce(sp.help_types, '{}'::public.help_type[]) as offered,
        coalesce(sp.categories_of_interest, '{}'::public.dream_category[]) as cats
    from public.profiles p
    left join public.supporter_profiles sp on sp.user_id = p.id
    where p.id = (select auth.uid())
),
-- Top-3 categories by the viewer's own recent engagement.
affinity as (
    select t.category
    from (
        select d.category,
            sum(case e.event_type
                when 'complete'       then 1.0
                when 'watch_progress' then coalesce(e.completion_ratio, 0.3)
                when 'save'           then 1.5
                when 'share'          then 1.5
                when 'offer_help'     then 1.5
                when 'follow'         then 1.0
                when 'skip'           then -0.3
                when 'not_relevant'   then -1.0
                else 0.0
            end) as pts
        from public.engagement_events e
        join public.dreams d on d.id = e.dream_id
        where e.user_id = (select auth.uid())
          and e.created_at > now() - interval '30 days'
        group by d.category
    ) t
    where t.pts > 0
    order by t.pts desc
    limit 3
),
-- Shared exclusions: never the viewer's own dreams; never dismissed; never
-- seen within the TTL window.
eligible as (
    select d.*
    from public.dreams d
    where d.owner_id <> (select auth.uid())
      and not exists (
          select 1
          from public.dream_seen s
          where s.user_id = (select auth.uid())
            and s.dream_id = d.id
            and (s.dismissed
                 or s.last_seen_at > now() - make_interval(days => p_seen_ttl_days))
      )
),
src_help_type as (
    select e.id, 'help_type_match' as source
    from eligible e, viewer v
    where e.help_types && v.offered
    order by e.created_at desc
    limit 120
),
src_skill as (
    select e.id, 'skill_overlap' as source
    from eligible e, viewer v
    where v.skills is not null
      and exists (
          select 1 from unnest(e.help_tags) as t
          where lower(trim(t)) = any(v.skills)
      )
    order by e.created_at desc
    limit 60
),
src_category as (
    select e.id, 'category_affinity' as source
    from eligible e, viewer v
    where e.category in (select a.category from affinity a)
       or e.category = any(v.cats)
    order by e.created_at desc
    limit 60
),
src_geo as (
    select e.id, 'geo' as source
    from eligible e, viewer v
    where v.loc is not null
      and nullif(lower(trim(coalesce(e.location, ''))), '') = v.loc
    order by e.created_at desc
    limit 40
),
src_followed as (
    select e.id, 'followed' as source
    from eligible e
    where e.owner_id in (
        select f.followed_id from public.follows f
        where f.follower_id = (select auth.uid())
    )
    order by e.created_at desc
    limit 30
),
src_fresh as (
    select e.id, 'fresh' as source
    from eligible e
    where e.created_at > now() - interval '48 hours'
    order by e.created_at desc
    limit 30
),
-- Fairness source: below-floor dreams, most-starved first. Restricted to
-- help-type-compatible dreams ("N *relevant* viewers"), but a viewer with no
-- declared capabilities — or a dream with no parseable needs — still matches.
src_underexposed as (
    select e.id, 'underexposed' as source
    from eligible e
    join public.dream_exposure_counters c on c.dream_id = e.id
    cross join viewer v
    where c.distinct_viewers < p_underexposed_viewer_floor
      and (v.offered = '{}'::public.help_type[]
           or e.help_types = '{}'::public.help_type[]
           or e.help_types && v.offered)
    order by c.distinct_viewers asc, e.created_at asc
    limit 40
),
unioned as (
    select * from src_help_type
    union all select * from src_skill
    union all select * from src_category
    union all select * from src_geo
    union all select * from src_followed
    union all select * from src_fresh
    union all select * from src_underexposed
    -- Future: union all select * from src_embedding
),
grouped as (
    select u.id, array_agg(distinct u.source) as sources
    from unioned u
    group by u.id
)
select
    d.id,
    d.owner_id,
    d.title,
    d.category,
    d.stage,
    d.location,
    d.help_tags,
    d.help_types,
    d.created_at,
    coalesce(c.offers_received, 0),
    coalesce(st.supporters_count, 0),
    coalesce(c.impressions, 0),
    coalesce(c.distinct_viewers, 0),
    exists (
        select 1 from public.follows f
        where f.follower_id = (select auth.uid()) and f.followed_id = d.owner_id
    ),
    exists (
        select 1 from public.dream_videos dv where dv.dream_id = d.id
    ),
    g.sources
from grouped g
join public.dreams d on d.id = g.id
left join public.dream_exposure_counters c on c.dream_id = d.id
left join public.dream_stats st on st.dream_id = d.id
limit p_limit
$$;

revoke execute on function public.get_feed_candidates(int, int, int) from public, anon;
grant execute on function public.get_feed_candidates(int, int, int) to authenticated;
