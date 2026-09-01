-- Connection-lifecycle instrumentation. The recommendation system is judged
-- on offer_sent -> accepted -> conversation_started -> support_delivered, so
-- every status transition is logged with a timestamp.
--
-- Mapping to the funnel:
--   offer_sent           = help_offer_events (null -> pending)
--   accepted             = help_offers.accepted_at
--   conversation_started = conversations.created_at (create_help_offer opens
--                          the conversation at offer time; join via
--                          help_offers.conversation_id)
--   support_delivered    = help_offers.completed_at (status 'completed')

alter table public.help_offers
    add column if not exists accepted_at timestamptz,
    add column if not exists completed_at timestamptz;

create table if not exists public.help_offer_events (
    id bigint generated always as identity primary key,
    offer_id uuid not null references public.help_offers(id) on delete cascade,
    dream_id uuid not null references public.dreams(id) on delete cascade,
    from_status public.help_offer_status,
    to_status public.help_offer_status not null,
    created_at timestamptz not null default now()
);

create index if not exists help_offer_events_offer_idx
    on public.help_offer_events (offer_id, created_at);

create index if not exists help_offer_events_dream_idx
    on public.help_offer_events (dream_id, created_at);

alter table public.help_offer_events enable row level security;

grant select on public.help_offer_events to authenticated;

drop policy if exists "offer events readable by supporter or dream owner"
    on public.help_offer_events;
create policy "offer events readable by supporter or dream owner"
    on public.help_offer_events
    for select
    to authenticated
    using (
        exists (
            select 1
            from public.help_offers o
            join public.dreams d on d.id = o.dream_id
            where o.id = offer_id
              and (o.supporter_id = (select auth.uid())
                   or d.owner_id = (select auth.uid()))
        )
    );
-- Writes only via trigger below.

-- BEFORE UPDATE: stamp lifecycle timestamps on first transition into a state.
create or replace function public.stamp_help_offer_timestamps()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
    if new.status is distinct from old.status then
        if new.status in ('accepted', 'in_progress') and new.accepted_at is null then
            new.accepted_at := now();
        end if;
        if new.status = 'completed' and new.completed_at is null then
            new.completed_at := now();
        end if;
    end if;
    return new;
end;
$$;

revoke execute on function public.stamp_help_offer_timestamps() from public, anon, authenticated;

drop trigger if exists help_offers_stamp_timestamps on public.help_offers;
create trigger help_offers_stamp_timestamps
    before update on public.help_offers
    for each row
    execute function public.stamp_help_offer_timestamps();

-- AFTER INSERT/UPDATE: append the transition log.
create or replace function public.log_help_offer_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if tg_op = 'INSERT' then
        insert into public.help_offer_events (offer_id, dream_id, from_status, to_status)
        values (new.id, new.dream_id, null, new.status);
    elsif new.status is distinct from old.status then
        insert into public.help_offer_events (offer_id, dream_id, from_status, to_status)
        values (new.id, new.dream_id, old.status, new.status);
    end if;
    return null;
end;
$$;

revoke execute on function public.log_help_offer_event() from public, anon, authenticated;

drop trigger if exists help_offers_log_event on public.help_offers;
create trigger help_offers_log_event
    after insert or update on public.help_offers
    for each row
    execute function public.log_help_offer_event();

-- Backfill existing offers: approximate timestamps from updated_at, and seed
-- one synthetic "offer_sent -> current status" event per offer so funnel
-- queries see pre-instrumentation history.
update public.help_offers
set accepted_at = updated_at
where accepted_at is null
  and status in ('accepted', 'in_progress', 'completed');

update public.help_offers
set completed_at = updated_at
where completed_at is null
  and status = 'completed';

insert into public.help_offer_events (offer_id, dream_id, from_status, to_status, created_at)
select o.id, o.dream_id, null, o.status, o.created_at
from public.help_offers o
where not exists (
    select 1 from public.help_offer_events e where e.offer_id = o.id
);
