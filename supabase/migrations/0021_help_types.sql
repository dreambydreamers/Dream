-- Canonical help-type taxonomy + supporter capability profiles.
--
-- help_type is the matching currency of the recommendation system: dreams
-- declare what they need (derived from free-text help_tags), supporters
-- declare what they can offer (supporter_profiles.help_types). Candidate
-- generation matches on the overlap of the two.

create type public.help_type as enum
    ('code', 'design', 'funding', 'mentorship', 'marketing', 'legal', 'space', 'other');

-- Normalizes a free-text tag ("Coding", "Network", …) to the canonical enum.
-- Legacy "Network" maps to mentorship (intros/connections are mentorship-adjacent).
create or replace function public.to_help_type(p_raw text)
returns public.help_type
language sql
immutable
set search_path = public, pg_temp
as $$
    select (case lower(trim(coalesce(p_raw, '')))
        when 'code'        then 'code'
        when 'coding'      then 'code'
        when 'engineering' then 'code'
        when 'development' then 'code'
        when 'developer'   then 'code'
        when 'design'      then 'design'
        when 'funding'     then 'funding'
        when 'investment'  then 'funding'
        when 'investor'    then 'funding'
        when 'mentorship'  then 'mentorship'
        when 'mentor'      then 'mentorship'
        when 'mentoring'   then 'mentorship'
        when 'network'     then 'mentorship'
        when 'networking'  then 'mentorship'
        when 'marketing'   then 'marketing'
        when 'legal'       then 'legal'
        when 'space'       then 'space'
        when 'venue'       then 'space'
        else 'other'
    end)::public.help_type
$$;

revoke execute on function public.to_help_type(text) from public, anon;
grant execute on function public.to_help_type(text) to authenticated;

-- dreams.help_types is derived from help_tags and kept in sync by trigger so
-- candidate generation can use an indexed enum-array overlap instead of
-- normalizing free text per query.
alter table public.dreams
    add column if not exists help_types public.help_type[] not null default '{}';

create or replace function public.sync_dream_help_types()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
    new.help_types := coalesce(
        (select array_agg(distinct public.to_help_type(t)) from unnest(new.help_tags) as t),
        '{}'::public.help_type[]);
    return new;
end;
$$;

revoke execute on function public.sync_dream_help_types() from public, anon, authenticated;

drop trigger if exists dreams_sync_help_types on public.dreams;
create trigger dreams_sync_help_types
    before insert or update of help_tags on public.dreams
    for each row
    execute function public.sync_dream_help_types();

-- Backfill existing rows directly (avoids re-firing unrelated update triggers
-- more than necessary; dreams_updated_at will still bump updated_at once).
update public.dreams
set help_types = coalesce(
    (select array_agg(distinct public.to_help_type(t)) from unnest(help_tags) as t),
    '{}'::public.help_type[]);

create index if not exists dreams_help_types_gin_idx
    on public.dreams using gin (help_types);

-- Supporter capability profile: what a user can offer, their capacity, and
-- declared interests. Skills + location stay on profiles (already editable).
create table if not exists public.supporter_profiles (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    help_types public.help_type[] not null default '{}',
    weekly_capacity_hours int not null default 2
        check (weekly_capacity_hours between 0 and 40),
    categories_of_interest public.dream_category[] not null default '{}',
    preferred_stages public.dream_stage[] not null default '{}',
    updated_at timestamptz not null default now()
);

alter table public.supporter_profiles enable row level security;

grant select, insert, update on public.supporter_profiles to authenticated;

drop policy if exists "supporter profiles: select own" on public.supporter_profiles;
create policy "supporter profiles: select own"
    on public.supporter_profiles
    for select
    to authenticated
    using (user_id = (select auth.uid()));

drop policy if exists "supporter profiles: insert own" on public.supporter_profiles;
create policy "supporter profiles: insert own"
    on public.supporter_profiles
    for insert
    to authenticated
    with check (user_id = (select auth.uid()));

drop policy if exists "supporter profiles: update own" on public.supporter_profiles;
create policy "supporter profiles: update own"
    on public.supporter_profiles
    for update
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

drop trigger if exists supporter_profiles_updated_at on public.supporter_profiles;
create trigger supporter_profiles_updated_at
    before update on public.supporter_profiles
    for each row
    execute function public.set_updated_at();
