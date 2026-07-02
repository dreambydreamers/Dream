-- One conversation per pair of users (Instagram-style DMs).
--
-- Previously every help offer opened its own conversation (dream_id set) and
-- video shares only reused conversations with dream_id null, so the same two
-- people could accumulate several chat threads. From now on all messaging
-- between two users — help offers, shares, plain texts — lands in a single
-- shared 1:1 thread. conversations.dream_id is retired (always null); dream
-- context lives on help_offers.dream_id and messages.shared_dream_id.

-- =========================================================
-- get_or_create_direct_conversation: the single source of truth
-- =========================================================
-- Internal helper for the SECURITY DEFINER RPCs below — not exposed via /rpc.
create or replace function get_or_create_direct_conversation(p_a uuid, p_b uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_conv uuid;
begin
    -- Serialize per pair so two concurrent calls can't both create a thread.
    perform pg_advisory_xact_lock(
        hashtextextended(least(p_a, p_b)::text || ':' || greatest(p_a, p_b)::text, 0));

    select c.id into v_conv
    from conversations c
    join conversation_participants a
      on a.conversation_id = c.id and a.user_id = p_a
    join conversation_participants b
      on b.conversation_id = c.id and b.user_id = p_b
    where (
        select count(*) from conversation_participants cp
        where cp.conversation_id = c.id
    ) = 2
    order by coalesce(c.last_message_at, c.created_at) desc
    limit 1;

    if v_conv is null then
        insert into conversations (dream_id) values (null) returning id into v_conv;
        insert into conversation_participants (conversation_id, user_id)
        values (v_conv, p_a), (v_conv, p_b);
    end if;

    return v_conv;
end;
$$;

revoke execute on function get_or_create_direct_conversation(uuid, uuid) from public;
revoke execute on function get_or_create_direct_conversation(uuid, uuid) from anon;
revoke execute on function get_or_create_direct_conversation(uuid, uuid) from authenticated;

-- =========================================================
-- Merge existing duplicate threads per user pair
-- =========================================================
-- Keeper = the oldest conversation of each pair. Messages carry their own
-- timestamps, so moving them preserves chronological order in the merged thread.
do $$
declare
    rec record;
    keeper uuid;
    dupes uuid[];
begin
    for rec in
        select array_agg(c.id order by c.created_at) as convs
        from conversations c
        join conversation_participants a on a.conversation_id = c.id
        join conversation_participants b
          on b.conversation_id = c.id and a.user_id < b.user_id
        where (
            select count(*) from conversation_participants cp
            where cp.conversation_id = c.id
        ) = 2
        group by a.user_id, b.user_id
        having count(*) > 1
    loop
        keeper := rec.convs[1];
        dupes  := rec.convs[2:];

        update messages      set conversation_id = keeper where conversation_id = any(dupes);
        update help_offers   set conversation_id = keeper where conversation_id = any(dupes);
        update notifications set conversation_id = keeper where conversation_id = any(dupes);

        -- Merge read receipts: a user has read the merged thread up to the
        -- latest point they had read any of its source threads.
        update conversation_participants kp
        set last_read_at = greatest(kp.last_read_at, sub.max_read)
        from (
            select user_id, max(last_read_at) as max_read
            from conversation_participants
            where conversation_id = any(dupes)
            group by user_id
        ) sub
        where kp.conversation_id = keeper and kp.user_id = sub.user_id;

        delete from conversations where id = any(dupes);

        update conversations c
        set last_message_at = m.created_at,
            last_message_preview = left(m.body, 140)
        from (
            select created_at, body from messages
            where conversation_id = keeper
            order by created_at desc limit 1
        ) m
        where c.id = keeper;
    end loop;
end $$;

-- Retire dream_id on 1:1 threads — a merged thread can span several dreams.
update conversations set dream_id = null where dream_id is not null;

-- =========================================================
-- create_help_offer: reuse the pair's thread
-- =========================================================
create or replace function create_help_offer(
    p_dream_id uuid,
    p_skill text,
    p_message text default ''
)
returns table (offer_id uuid, conversation_id uuid, already_existed boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_caller uuid := auth.uid();
    v_owner uuid;
    v_offer uuid;
    v_conv uuid;
    v_body text;
begin
    if v_caller is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;

    select owner_id into v_owner from dreams where id = p_dream_id;
    if v_owner is null then
        raise exception 'Dream not found' using errcode = 'P0002';
    end if;
    if v_owner = v_caller then
        raise exception 'You cannot offer help on your own dream' using errcode = '42501';
    end if;

    -- Dedupe: reuse any active offer (and its conversation) from this supporter.
    select id, help_offers.conversation_id into v_offer, v_conv
    from help_offers
    where dream_id = p_dream_id
      and supporter_id = v_caller
      and status in ('pending', 'accepted', 'in_progress')
    limit 1;

    if v_offer is not null then
        return query select v_offer, v_conv, true;
        return;
    end if;

    v_conv := get_or_create_direct_conversation(v_caller, v_owner);

    insert into help_offers (dream_id, supporter_id, skill, message, status, conversation_id)
    values (p_dream_id, v_caller, p_skill, coalesce(p_message, ''), 'pending', v_conv)
    returning id into v_offer;

    v_body := 'Offered to help with ' || p_skill
              || case when coalesce(p_message, '') <> '' then ': ' || p_message else '' end;
    insert into messages (conversation_id, sender_id, body, kind)
    values (v_conv, v_caller, v_body, 'system');

    insert into notifications (user_id, type, actor_id, dream_id, offer_id, conversation_id, preview)
    values (v_owner, 'offer_received', v_caller, p_dream_id, v_offer, v_conv,
            'New offer to help with ' || p_skill);

    return query select v_offer, v_conv, false;
end;
$$;

-- =========================================================
-- share_dream_video: reuse the pair's thread
-- =========================================================
create or replace function share_dream_video(
    p_recipient_id uuid,
    p_dream_id uuid,
    p_video_id uuid default null,
    p_note text default ''
)
returns table (conversation_id uuid, message_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_caller uuid := auth.uid();
    v_recipient_exists boolean;
    v_dream_title text;
    v_video_title text;
    v_conv uuid;
    v_msg uuid;
    v_body text;
begin
    if v_caller is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;
    if p_recipient_id is null or p_recipient_id = v_caller then
        raise exception 'Pick someone else to share with' using errcode = '22023';
    end if;

    select exists (select 1 from profiles where id = p_recipient_id)
        into v_recipient_exists;
    if not v_recipient_exists then
        raise exception 'Recipient not found' using errcode = 'P0002';
    end if;

    select title into v_dream_title from dreams where id = p_dream_id;
    if v_dream_title is null then
        raise exception 'Dream not found' using errcode = 'P0002';
    end if;

    if p_video_id is not null then
        select coalesce(title, v_dream_title)
            into v_video_title
        from dream_videos
        where id = p_video_id and dream_id = p_dream_id;

        if v_video_title is null then
            raise exception 'Video not found' using errcode = 'P0002';
        end if;
    else
        v_video_title := v_dream_title;
    end if;

    v_conv := get_or_create_direct_conversation(v_caller, p_recipient_id);

    v_body := 'Shared "' || v_video_title || '"';
    if coalesce(trim(p_note), '') <> '' then
        v_body := v_body || ': ' || trim(p_note);
    end if;

    insert into messages (
        conversation_id, sender_id, body, kind, shared_dream_id, shared_video_id
    )
    values (
        v_conv, v_caller, v_body, 'dream_share', p_dream_id, p_video_id
    )
    returning id into v_msg;

    return query select v_conv, v_msg;
end;
$$;
