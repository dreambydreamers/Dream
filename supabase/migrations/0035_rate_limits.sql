-- 0035_rate_limits.sql
-- Production-readiness audit (2026-08): server-side write throttling.
--
-- Correction to the audit's first pass: unthrottled `log_engagement_batch`
-- does NOT let a client manipulate ranking. The fairness pass keys on
-- `distinct_viewers` (FairnessPass.swift), which is one row per (user, dream)
-- and so is capped at 1 per account no matter how many events are sent, and
-- `Scoring.swift` deliberately consumes neither impressions nor viewers. The
-- real exposure is write amplification: an authenticated client could append
-- unbounded rows to engagement_events (and flood comments/DMs) at will. That
-- is a cost and spam problem, so this throttles writes and leaves the
-- ranking invariants — and their pgTAP assertions — untouched.
--
-- Fixed-window counters, per (user, bucket). Cheap: one upsert per call.

create table if not exists public.rate_limit_counters (
    user_id uuid not null references auth.users(id) on delete cascade,
    bucket text not null,
    window_started_at timestamptz not null default now(),
    used int not null default 0,
    primary key (user_id, bucket)
);

-- RLS on with NO policies and no grants: unreachable from the Data API. Only
-- the SECURITY DEFINER function below touches it.
alter table public.rate_limit_counters enable row level security;
revoke all on public.rate_limit_counters from public, anon, authenticated;

-- Adds `p_cost` to the caller's window and reports whether they are still
-- within budget. The window resets lazily on first use after it expires.
create or replace function public.consume_rate_limit(
    p_bucket text,
    p_limit int,
    p_window interval,
    p_cost int default 1
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_user uuid := auth.uid();
    v_used int;
begin
    -- No authenticated user means this is the service role, a migration, a
    -- backfill or a seed script — not the threat model, and throttling them
    -- would break admin writes outright. (The `anon` role cannot reach any of
    -- the throttled tables: every insert policy is `to authenticated`.)
    if v_user is null then
        return true;
    end if;
    if p_cost <= 0 then
        return true;
    end if;

    insert into public.rate_limit_counters as r (user_id, bucket, window_started_at, used)
    values (v_user, p_bucket, now(), p_cost)
    on conflict (user_id, bucket) do update
        set window_started_at = case
                when r.window_started_at < now() - p_window then now()
                else r.window_started_at
            end,
            used = case
                when r.window_started_at < now() - p_window then p_cost
                else r.used + p_cost
            end
    returning r.used into v_used;

    return v_used <= p_limit;
end;
$$;

revoke execute on function public.consume_rate_limit(text, int, interval, int)
    from public, anon, authenticated;

-- =========================================================
-- 1. Engagement ingestion.
-- =========================================================
-- Budget is counted in EVENTS, not calls, so batching cannot evade it.
-- 1200 per 5 minutes is far above real use (the client flushes at 10 events /
-- 15 s, and heavy scrolling produces roughly two events per card) while
-- capping a scripted client at a bounded write rate.
--
-- Over budget sheds the batch silently rather than raising: EngagementLogger
-- keeps its buffer on error and retries, so raising here would spin a client
-- that is already sending too much. Analytics events are lossy by nature.

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

    if not public.consume_rate_limit(
        'engagement', 1200, interval '5 minutes', jsonb_array_length(p_events)
    ) then
        return;
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

-- =========================================================
-- 2. Comments and messages.
-- =========================================================
-- These are direct table inserts under RLS, so the throttle is a trigger.
-- Limits are generous for a person and hostile to a script.

create or replace function public.throttle_comment_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not public.consume_rate_limit('comment', 30, interval '5 minutes') then
        raise exception 'You are commenting too quickly. Try again in a few minutes.'
            using errcode = '53400';
    end if;
    return new;
end;
$$;

revoke execute on function public.throttle_comment_insert() from public, anon, authenticated;

drop trigger if exists dream_comments_throttle on public.dream_comments;
create trigger dream_comments_throttle
    before insert on public.dream_comments
    for each row
    execute function public.throttle_comment_insert();

create or replace function public.throttle_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    -- Only user-authored kinds. 'system' rows are minted by the offer RPCs on
    -- behalf of a workflow and must never be blocked by the sender's budget.
    if new.kind not in ('text', 'dream_share') then
        return new;
    end if;
    if not public.consume_rate_limit('message', 120, interval '5 minutes') then
        raise exception 'You are sending messages too quickly. Try again in a few minutes.'
            using errcode = '53400';
    end if;
    return new;
end;
$$;

revoke execute on function public.throttle_message_insert() from public, anon, authenticated;

drop trigger if exists messages_throttle on public.messages;
create trigger messages_throttle
    before insert on public.messages
    for each row
    execute function public.throttle_message_insert();

-- Likes are cheap but trivially scriptable; keep a ceiling on them too.
create or replace function public.throttle_like_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not public.consume_rate_limit('like', 300, interval '5 minutes') then
        raise exception 'Too many likes too quickly. Try again in a few minutes.'
            using errcode = '53400';
    end if;
    return new;
end;
$$;

revoke execute on function public.throttle_like_insert() from public, anon, authenticated;

drop trigger if exists dream_likes_throttle on public.dream_likes;
create trigger dream_likes_throttle
    before insert on public.dream_likes
    for each row
    execute function public.throttle_like_insert();
