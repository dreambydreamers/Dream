-- Profile features: user-to-user follows, a user-selectable "main" dream,
-- and a per-profile aggregate stats view (videos / followers / following / offers).

-- =========================================================
-- follows  (follower -> followed user)
-- =========================================================

create table follows (
    follower_id uuid not null references profiles(id) on delete cascade,
    followed_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (follower_id, followed_id),
    check (follower_id <> followed_id)
);

create index follows_followed_id_idx on follows(followed_id);

alter table follows enable row level security;

create policy "follows are readable by everyone"
    on follows for select using (true);

create policy "users follow as themselves"
    on follows for insert with check (auth.uid() = follower_id);

create policy "users unfollow themselves"
    on follows for delete using (auth.uid() = follower_id);

-- =========================================================
-- Featured ("main") dream per user
-- =========================================================

alter table dreams add column is_featured boolean not null default false;

-- At most one featured dream per owner.
create unique index dreams_featured_per_owner_idx on dreams(owner_id) where is_featured;

-- =========================================================
-- Per-profile aggregate stats
-- =========================================================

create or replace view profile_stats as
select
    p.id as profile_id,
    (select count(*) from dream_videos dv
        join dreams d on d.id = dv.dream_id
        where d.owner_id = p.id)::int as videos_count,
    (select count(*) from follows f where f.followed_id = p.id)::int as followers_count,
    (select count(*) from follows f where f.follower_id = p.id)::int as following_count,
    (select count(*) from help_offers ho
        join dreams d on d.id = ho.dream_id
        where d.owner_id = p.id
        and ho.status in ('pending', 'accepted'))::int as offers_count
from profiles p;

-- Run with the caller's permissions/RLS (matches dream_stats; advisor lint).
alter view profile_stats set (security_invoker = on);
