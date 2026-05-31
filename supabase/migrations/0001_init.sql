-- Dream initial schema
-- Tables: profiles, dreams, journey_steps, dream_videos, supporters, help_offers
-- All tables have RLS enabled.

-- =========================================================
-- Enums
-- =========================================================

create type dream_category as enum (
    'tech', 'food', 'art', 'impact',
    'education', 'health', 'music', 'sport'
);

create type dream_stage as enum (
    'idea', 'early', 'needs', 'almost'
);

create type help_offer_status as enum (
    'pending', 'accepted', 'declined', 'withdrawn'
);

-- =========================================================
-- profiles  (1:1 with auth.users)
-- =========================================================

create table profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    handle text unique,
    name text,
    avatar_seed int not null default floor(random() * 1000)::int,
    location text,
    skills text[] not null default '{}',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table profiles enable row level security;

create policy "profiles are readable by everyone"
    on profiles for select using (true);

create policy "users can insert their own profile"
    on profiles for insert with check (auth.uid() = id);

create policy "users can update their own profile"
    on profiles for update using (auth.uid() = id);

-- Auto-create profile row on signup
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id) values (new.id)
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function handle_new_user();

-- =========================================================
-- dreams
-- =========================================================

create table dreams (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references profiles(id) on delete cascade,
    title text not null,
    description text not null default '',
    category dream_category not null,
    stage dream_stage not null default 'idea',
    location text,
    help_tags text[] not null default '{}',
    views_count int not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index dreams_owner_id_idx on dreams(owner_id);
create index dreams_category_idx on dreams(category);
create index dreams_created_at_idx on dreams(created_at desc);

alter table dreams enable row level security;

create policy "dreams are readable by everyone"
    on dreams for select using (true);

create policy "users can insert their own dreams"
    on dreams for insert with check (auth.uid() = owner_id);

create policy "owners can update their dreams"
    on dreams for update using (auth.uid() = owner_id);

create policy "owners can delete their dreams"
    on dreams for delete using (auth.uid() = owner_id);

-- =========================================================
-- journey_steps
-- =========================================================

create table journey_steps (
    id uuid primary key default gen_random_uuid(),
    dream_id uuid not null references dreams(id) on delete cascade,
    stage text not null,
    date_label text not null,
    note text not null default '',
    done boolean not null default false,
    sort_order int not null default 0,
    created_at timestamptz not null default now()
);

create index journey_steps_dream_id_idx on journey_steps(dream_id, sort_order);

alter table journey_steps enable row level security;

create policy "journey steps are readable by everyone"
    on journey_steps for select using (true);

create policy "dream owners manage journey steps"
    on journey_steps for all
    using (exists (select 1 from dreams d where d.id = dream_id and d.owner_id = auth.uid()))
    with check (exists (select 1 from dreams d where d.id = dream_id and d.owner_id = auth.uid()));

-- =========================================================
-- dream_videos
-- =========================================================

create table dream_videos (
    id uuid primary key default gen_random_uuid(),
    dream_id uuid not null references dreams(id) on delete cascade,
    storage_path text not null,
    poster_path text,
    duration_ms int,
    width int,
    height int,
    is_primary boolean not null default false,
    created_at timestamptz not null default now()
);

create index dream_videos_dream_id_idx on dream_videos(dream_id);
create unique index dream_videos_primary_idx on dream_videos(dream_id) where is_primary;

alter table dream_videos enable row level security;

create policy "dream videos are readable by everyone"
    on dream_videos for select using (true);

create policy "dream owners manage videos"
    on dream_videos for all
    using (exists (select 1 from dreams d where d.id = dream_id and d.owner_id = auth.uid()))
    with check (exists (select 1 from dreams d where d.id = dream_id and d.owner_id = auth.uid()));

-- =========================================================
-- supporters  (user follows / backs a dream)
-- =========================================================

create table supporters (
    dream_id uuid not null references dreams(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (dream_id, user_id)
);

create index supporters_user_id_idx on supporters(user_id);

alter table supporters enable row level security;

create policy "supporters are readable by everyone"
    on supporters for select using (true);

create policy "users add themselves as supporter"
    on supporters for insert with check (auth.uid() = user_id);

create policy "users remove themselves as supporter"
    on supporters for delete using (auth.uid() = user_id);

-- =========================================================
-- help_offers
-- =========================================================

create table help_offers (
    id uuid primary key default gen_random_uuid(),
    dream_id uuid not null references dreams(id) on delete cascade,
    supporter_id uuid not null references profiles(id) on delete cascade,
    skill text not null,
    message text not null default '',
    status help_offer_status not null default 'pending',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index help_offers_dream_id_idx on help_offers(dream_id);
create index help_offers_supporter_id_idx on help_offers(supporter_id);

alter table help_offers enable row level security;

create policy "offers visible to dream owner and offer author"
    on help_offers for select
    using (
        auth.uid() = supporter_id
        or exists (select 1 from dreams d where d.id = dream_id and d.owner_id = auth.uid())
    );

create policy "supporters create their own offers"
    on help_offers for insert with check (auth.uid() = supporter_id);

create policy "supporter updates own offer; owner updates status"
    on help_offers for update using (
        auth.uid() = supporter_id
        or exists (select 1 from dreams d where d.id = dream_id and d.owner_id = auth.uid())
    );

-- =========================================================
-- Derived counts view
-- =========================================================

create or replace view dream_stats as
select
    d.id as dream_id,
    coalesce(s.supporters_count, 0) as supporters_count,
    coalesce(o.offers_count, 0) as offers_count
from dreams d
left join (
    select dream_id, count(*)::int as supporters_count
    from supporters group by dream_id
) s on s.dream_id = d.id
left join (
    select dream_id, count(*)::int as offers_count
    from help_offers where status in ('pending', 'accepted') group by dream_id
) o on o.dream_id = d.id;

-- =========================================================
-- updated_at trigger
-- =========================================================

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger profiles_updated_at before update on profiles
    for each row execute function set_updated_at();
create trigger dreams_updated_at before update on dreams
    for each row execute function set_updated_at();
create trigger help_offers_updated_at before update on help_offers
    for each row execute function set_updated_at();
