-- Atomic operations for the help / collaboration loop.
--
-- All cross-user writes go through SECURITY DEFINER functions so a single call
-- does its whole job atomically and authorization lives in one place. Each
-- function re-derives the caller from auth.uid() and never trusts a passed id.

-- =========================================================
-- create_help_offer: the "I can help" action
-- =========================================================
-- Creates an offer, opens a conversation between supporter + owner, posts a
-- system message, and notifies the owner. Idempotent: a second tap while an
-- active offer exists returns the existing offer/conversation instead of a dupe.
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

    insert into conversations (dream_id) values (p_dream_id) returning id into v_conv;

    insert into conversation_participants (conversation_id, user_id, role)
    values (v_conv, v_owner, 'owner'), (v_conv, v_caller, 'helper');

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
-- respond_to_help_offer: owner advances the lifecycle
-- =========================================================
create or replace function respond_to_help_offer(
    p_offer_id uuid,
    p_status help_offer_status
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_caller uuid := auth.uid();
    v_owner uuid;
    v_supporter uuid;
    v_conv uuid;
    v_skill text;
begin
    if v_caller is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;
    if p_status::text not in ('accepted', 'rejected', 'in_progress', 'completed', 'cancelled') then
        raise exception 'Invalid status transition' using errcode = '22023';
    end if;

    select ho.supporter_id, ho.conversation_id, ho.skill, d.owner_id
        into v_supporter, v_conv, v_skill, v_owner
    from help_offers ho
    join dreams d on d.id = ho.dream_id
    where ho.id = p_offer_id;

    if v_owner is null then
        raise exception 'Offer not found' using errcode = 'P0002';
    end if;
    if v_owner <> v_caller then
        raise exception 'Only the dream owner can respond to this offer' using errcode = '42501';
    end if;

    update help_offers set status = p_status where id = p_offer_id;

    if v_conv is not null then
        insert into messages (conversation_id, sender_id, body, kind)
        values (v_conv, v_caller,
                case p_status::text
                    when 'accepted' then 'Accepted your offer to help with ' || v_skill
                    when 'rejected' then 'Declined the offer to help with ' || v_skill
                    when 'in_progress' then 'Marked the help with ' || v_skill || ' as in progress'
                    when 'completed' then 'Marked the help with ' || v_skill || ' as completed'
                    else 'Cancelled the help with ' || v_skill
                end,
                'system');
    end if;

    insert into notifications (user_id, type, actor_id, dream_id, offer_id, conversation_id, preview)
    select v_supporter, 'offer_' || p_status::text, v_caller, ho.dream_id, p_offer_id, v_conv,
           'Your offer to help with ' || v_skill || ' is ' || replace(p_status::text, '_', ' ')
    from help_offers ho where ho.id = p_offer_id;
end;
$$;

-- =========================================================
-- cancel_help_offer: supporter withdraws their own offer
-- =========================================================
create or replace function cancel_help_offer(p_offer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_caller uuid := auth.uid();
    v_supporter uuid;
    v_owner uuid;
    v_conv uuid;
    v_skill text;
    v_dream uuid;
begin
    if v_caller is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;

    select ho.supporter_id, ho.conversation_id, ho.skill, ho.dream_id, d.owner_id
        into v_supporter, v_conv, v_skill, v_dream, v_owner
    from help_offers ho
    join dreams d on d.id = ho.dream_id
    where ho.id = p_offer_id;

    if v_supporter is null then
        raise exception 'Offer not found' using errcode = 'P0002';
    end if;
    if v_supporter <> v_caller then
        raise exception 'Only the offer author can cancel it' using errcode = '42501';
    end if;

    update help_offers set status = 'cancelled' where id = p_offer_id;

    if v_conv is not null then
        insert into messages (conversation_id, sender_id, body, kind)
        values (v_conv, v_caller, 'Withdrew the offer to help with ' || v_skill, 'system');
    end if;

    insert into notifications (user_id, type, actor_id, dream_id, offer_id, conversation_id, preview)
    values (v_owner, 'offer_cancelled', v_caller, v_dream, p_offer_id, v_conv,
            replace(v_skill, '_', ' ') || ' offer was withdrawn');
end;
$$;

-- =========================================================
-- mark_conversation_read: read receipts + clears msg notifications
-- =========================================================
create or replace function mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_caller uuid := auth.uid();
begin
    if v_caller is null or not is_conversation_participant(p_conversation_id, v_caller) then
        raise exception 'Not a participant' using errcode = '42501';
    end if;

    update conversation_participants
        set last_read_at = now()
        where conversation_id = p_conversation_id and user_id = v_caller;

    update notifications
        set read_at = now()
        where user_id = v_caller
          and conversation_id = p_conversation_id
          and type = 'new_message'
          and read_at is null;
end;
$$;

-- =========================================================
-- notification read helpers
-- =========================================================
create or replace function mark_notifications_read(p_ids uuid[])
returns void
language sql
security definer
set search_path = public
as $$
    update notifications set read_at = now()
    where id = any(p_ids) and user_id = auth.uid() and read_at is null;
$$;

create or replace function mark_all_notifications_read()
returns void
language sql
security definer
set search_path = public
as $$
    update notifications set read_at = now()
    where user_id = auth.uid() and read_at is null;
$$;

-- =========================================================
-- Grants
-- =========================================================
grant execute on function create_help_offer(uuid, text, text) to authenticated;
grant execute on function respond_to_help_offer(uuid, help_offer_status) to authenticated;
grant execute on function cancel_help_offer(uuid) to authenticated;
grant execute on function mark_conversation_read(uuid) to authenticated;
grant execute on function mark_notifications_read(uuid[]) to authenticated;
grant execute on function mark_all_notifications_read() to authenticated;
