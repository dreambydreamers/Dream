-- Messaging + notifications for the Activity tab.
--
-- A help offer opens one conversation between the supporter and the dream owner.
-- Access is strictly participant-only (enforced by RLS). Encryption is provided
-- by Supabase transport (TLS) + at-rest disk encryption; no plaintext is
-- readable by non-participants.

-- =========================================================
-- conversations
-- =========================================================

create table conversations (
    id uuid primary key default gen_random_uuid(),
    dream_id uuid references dreams(id) on delete set null,
    last_message_at timestamptz,
    last_message_preview text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index conversations_last_message_idx on conversations(last_message_at desc);
alter table conversations enable row level security;

-- =========================================================
-- conversation_participants
-- =========================================================

create table conversation_participants (
    conversation_id uuid not null references conversations(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    role text not null default 'member',   -- 'owner' (dream owner) | 'helper'
    last_read_at timestamptz,              -- read receipts
    created_at timestamptz not null default now(),
    primary key (conversation_id, user_id)
);

create index conversation_participants_user_idx on conversation_participants(user_id);
alter table conversation_participants enable row level security;

-- Membership check used by RLS policies below. SECURITY DEFINER so policies on
-- conversation_participants can call it without recursing into their own RLS.
create or replace function is_conversation_participant(c uuid, u uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
    select exists (
        select 1 from conversation_participants
        where conversation_id = c and user_id = u
    );
$$;

-- =========================================================
-- messages
-- =========================================================

create table messages (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references conversations(id) on delete cascade,
    sender_id uuid not null references profiles(id) on delete cascade,
    body text not null default '',
    kind text not null default 'text',     -- 'text' | 'system'
    created_at timestamptz not null default now()
);

create index messages_conversation_idx on messages(conversation_id, created_at);
alter table messages enable row level security;

-- =========================================================
-- notifications  (in-app only)
-- =========================================================

create table notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references profiles(id) on delete cascade,  -- recipient
    type text not null,    -- offer_received | offer_accepted | offer_rejected
                           -- | offer_in_progress | offer_completed | offer_cancelled | new_message
    actor_id uuid references profiles(id) on delete set null,
    dream_id uuid references dreams(id) on delete cascade,
    offer_id uuid references help_offers(id) on delete cascade,
    conversation_id uuid references conversations(id) on delete cascade,
    preview text not null default '',
    read_at timestamptz,
    created_at timestamptz not null default now()
);

create index notifications_user_idx on notifications(user_id, created_at desc);
alter table notifications enable row level security;

-- =========================================================
-- help_offers <-> conversations link + duplicate prevention
-- =========================================================

alter table help_offers
    add constraint help_offers_conversation_id_fkey
    foreign key (conversation_id) references conversations(id) on delete set null;

-- One active offer per (dream, supporter): prevents duplicate "I can help" taps.
-- References 'in_progress', which is why this lives here (0008's transaction
-- couldn't reference the freshly-added enum value).
create unique index help_offers_active_uniq
    on help_offers (dream_id, supporter_id)
    where status in ('pending', 'accepted', 'in_progress');

-- =========================================================
-- RLS policies
-- =========================================================

-- conversations: participants only. Writes happen through SECURITY DEFINER RPCs.
create policy "participants read their conversations"
    on conversations for select
    using (is_conversation_participant(id, auth.uid()));

-- conversation_participants: a participant can see every member row of their
-- conversations (needed to render the other person + their read receipt).
create policy "participants read membership"
    on conversation_participants for select
    using (
        user_id = auth.uid()
        or is_conversation_participant(conversation_id, auth.uid())
    );

-- messages: participants read; participants send only as themselves; immutable.
create policy "participants read messages"
    on messages for select
    using (is_conversation_participant(conversation_id, auth.uid()));

create policy "participants send messages"
    on messages for insert
    with check (
        sender_id = auth.uid()
        and is_conversation_participant(conversation_id, auth.uid())
    );

-- notifications: recipient-only read; recipient may mark read. Inserts come from
-- SECURITY DEFINER triggers/RPCs (no client insert policy).
create policy "recipients read their notifications"
    on notifications for select
    using (user_id = auth.uid());

create policy "recipients update their notifications"
    on notifications for update
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- =========================================================
-- Triggers
-- =========================================================

-- On a new message: bump the conversation's last-message summary and notify the
-- other participant(s). SECURITY DEFINER so it can write conversations (no user
-- UPDATE policy) and notifications (no user INSERT policy).
create or replace function on_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    update conversations
        set last_message_at = new.created_at,
            last_message_preview = left(new.body, 140),
            updated_at = now()
        where id = new.conversation_id;

    -- Only human messages raise a new_message notification; system messages
    -- already carry their own offer_* notification from the RPC that posted them.
    if new.kind = 'text' then
        insert into notifications (user_id, type, actor_id, conversation_id, dream_id, preview)
        select cp.user_id, 'new_message', new.sender_id, new.conversation_id, c.dream_id, left(new.body, 140)
        from conversation_participants cp
        join conversations c on c.id = cp.conversation_id
        where cp.conversation_id = new.conversation_id
          and cp.user_id <> new.sender_id;
    end if;

    return new;
end;
$$;

create trigger messages_after_insert
    after insert on messages
    for each row execute function on_message_insert();

create trigger conversations_updated_at before update on conversations
    for each row execute function set_updated_at();

-- =========================================================
-- Realtime
-- =========================================================

-- Full row images so UPDATE/DELETE realtime payloads carry all columns
-- (status changes, read receipts, read_at, etc.). Realtime still applies each
-- table's RLS SELECT policy per subscriber.
alter table messages replica identity full;
alter table notifications replica identity full;
alter table conversation_participants replica identity full;
alter table conversations replica identity full;
alter table help_offers replica identity full;

alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table conversation_participants;
alter publication supabase_realtime add table conversations;
alter publication supabase_realtime add table help_offers;
