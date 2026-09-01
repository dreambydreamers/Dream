-- Engagement event log, per-viewer seen-set, and per-dream exposure counters.
--
-- Design invariants (do not weaken):
--   * engagement_events feed ONLY the viewer's own affinity profile. Nothing
--     in this schema aggregates watch/skip behavior into a per-dream quality
--     signal — a fast skip means "wrong viewer", not "worse dream".
--   * dream_seen is one row per (user, dream), so repeated views/skips by one
--     viewer can never inflate distinct_viewers.
--   * dream_exposure_counters exist so the fairness pass can find dreams below
--     the minimum-exposure floor; they are written only by SECURITY DEFINER
--     paths, never directly by clients.

create type public.engagement_event_type as enum
    ('view', 'watch_progress', 'complete', 'skip', 'offer_help',
     'comment', 'save', 'share', 'follow', 'not_relevant');

create table if not exists public.engagement_events (
    id bigint generated always as identity primary key,
    user_id uuid not null references public.profiles(id) on delete cascade,
    dream_id uuid not null references public.dreams(id) on delete cascade,
    event_type public.engagement_event_type not null,
    watch_ms int check (watch_ms >= 0),
    video_duration_ms int check (video_duration_ms > 0),
    completion_ratio numeric generated always as (
        case when video_duration_ms > 0
             then least(watch_ms::numeric / video_duration_ms, 1)
        end) stored,
    created_at timestamptz not null default now()
);

create index if not exists engagement_events_user_recent_idx
    on public.engagement_events (user_id, created_at desc);

create index if not exists engagement_events_dream_type_idx
    on public.engagement_events (dream_id, event_type, created_at desc);

alter table public.engagement_events enable row level security;

grant select on public.engagement_events to authenticated;

drop policy if exists "engagement events: select own" on public.engagement_events;
create policy "engagement events: select own"
    on public.engagement_events
    for select
    to authenticated
    using (user_id = (select auth.uid()));
-- Writes go through log_engagement_batch only.

-- Per-viewer seen-set. Drives feed exclusion (TTL'd) and dismissal.
create table if not exists public.dream_seen (
    user_id uuid not null references public.profiles(id) on delete cascade,
    dream_id uuid not null references public.dreams(id) on delete cascade,
    first_seen_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    seen_count int not null default 1,
    dismissed boolean not null default false,
    primary key (user_id, dream_id)
);

create index if not exists dream_seen_dream_first_idx
    on public.dream_seen (dream_id, first_seen_at);

alter table public.dream_seen enable row level security;

grant select on public.dream_seen to authenticated;

drop policy if exists "dream seen: select own" on public.dream_seen;
create policy "dream seen: select own"
    on public.dream_seen
    for select
    to authenticated
    using (user_id = (select auth.uid()));
-- Writes go through log_engagement_batch only.

-- Per-dream exposure counters, readable by everyone signed in (the ranker
-- needs them for the under-served boost), written only by triggers/RPCs.
create table if not exists public.dream_exposure_counters (
    dream_id uuid primary key references public.dreams(id) on delete cascade,
    impressions bigint not null default 0,
    distinct_viewers bigint not null default 0,
    offers_received bigint not null default 0,
    last_impression_at timestamptz
);

alter table public.dream_exposure_counters enable row level security;

grant select on public.dream_exposure_counters to authenticated;

drop policy if exists "exposure counters readable by signed-in users" on public.dream_exposure_counters;
create policy "exposure counters readable by signed-in users"
    on public.dream_exposure_counters
    for select
    to authenticated
    using (true);

-- Backfill: one counter row per existing dream; offers_received counts every
-- offer ever sent (a rejected offer was still attention received).
insert into public.dream_exposure_counters (dream_id, offers_received)
select d.id, coalesce(o.cnt, 0)
from public.dreams d
left join (
    select dream_id, count(*) as cnt
    from public.help_offers
    group by dream_id
) o on o.dream_id = d.id
on conflict (dream_id) do nothing;

-- Counter row is created with the dream.
create or replace function public.init_dream_exposure_counters()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.dream_exposure_counters (dream_id)
    values (new.id)
    on conflict (dream_id) do nothing;
    return new;
end;
$$;

revoke execute on function public.init_dream_exposure_counters() from public, anon, authenticated;

drop trigger if exists dreams_init_exposure_counters on public.dreams;
create trigger dreams_init_exposure_counters
    after insert on public.dreams
    for each row
    execute function public.init_dream_exposure_counters();

-- Every new offer bumps offers_received (feeds the under-served boost decay).
create or replace function public.bump_offers_received()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.dream_exposure_counters (dream_id, offers_received)
    values (new.dream_id, 1)
    on conflict (dream_id) do update
        set offers_received = public.dream_exposure_counters.offers_received + 1;
    return null;
end;
$$;

revoke execute on function public.bump_offers_received() from public, anon, authenticated;

drop trigger if exists help_offers_bump_offers_received on public.help_offers;
create trigger help_offers_bump_offers_received
    after insert on public.help_offers
    for each row
    execute function public.bump_offers_received();

-- Batched event ingestion. The app buffers events and flushes them here.
-- 'view' maintains the seen-set + impression counters; 'not_relevant' marks
-- the dream dismissed for this viewer. Everything else is log-only.
create or replace function public.log_engagement_batch(p_events jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_user uuid := auth.uid();
    v_event jsonb;
    v_dream uuid;
    v_type public.engagement_event_type;
    v_watch_ms int;
    v_duration_ms int;
    v_new_viewer boolean;
begin
    if v_user is null then
        raise exception 'not authenticated';
    end if;
    if p_events is null or jsonb_typeof(p_events) <> 'array' then
        raise exception 'p_events must be a json array';
    end if;
    if jsonb_array_length(p_events) > 100 then
        raise exception 'batch too large (max 100 events)';
    end if;

    for v_event in select * from jsonb_array_elements(p_events)
    loop
        v_dream := (v_event->>'dream_id')::uuid;
        if v_dream is null then
            raise exception 'event missing dream_id';
        end if;
        v_type := (v_event->>'event_type')::public.engagement_event_type;
        v_watch_ms := greatest(nullif(v_event->>'watch_ms', '')::int, 0);
        v_duration_ms := nullif(greatest(nullif(v_event->>'video_duration_ms', '')::int, 0), 0);

        -- Dream may have been deleted between display and flush; drop quietly.
        if not exists (select 1 from public.dreams d where d.id = v_dream) then
            continue;
        end if;

        insert into public.engagement_events
            (user_id, dream_id, event_type, watch_ms, video_duration_ms)
        values (v_user, v_dream, v_type, v_watch_ms, v_duration_ms);

        if v_type = 'view' then
            insert into public.dream_seen as ds (user_id, dream_id)
            values (v_user, v_dream)
            on conflict (user_id, dream_id) do update
                set last_seen_at = now(),
                    seen_count = ds.seen_count + 1
            returning (xmax = 0) into v_new_viewer;

            insert into public.dream_exposure_counters as c
                (dream_id, impressions, distinct_viewers, last_impression_at)
            values (v_dream, 1, case when v_new_viewer then 1 else 0 end, now())
            on conflict (dream_id) do update
                set impressions = c.impressions + 1,
                    distinct_viewers = c.distinct_viewers
                        + case when v_new_viewer then 1 else 0 end,
                    last_impression_at = now();
        elsif v_type = 'not_relevant' then
            insert into public.dream_seen as ds (user_id, dream_id, dismissed)
            values (v_user, v_dream, true)
            on conflict (user_id, dream_id) do update
                set dismissed = true,
                    last_seen_at = now();
        end if;
    end loop;
end;
$$;

revoke execute on function public.log_engagement_batch(jsonb) from public, anon;
grant execute on function public.log_engagement_batch(jsonb) to authenticated;
