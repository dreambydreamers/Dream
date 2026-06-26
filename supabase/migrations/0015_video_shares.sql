-- In-app video sharing.
-- A share is a normal chat message with a small amount of structured metadata
-- so the chat can render a video card instead of plain text.

alter table messages
    add column if not exists shared_dream_id uuid references dreams(id) on delete set null,
    add column if not exists shared_video_id uuid references dream_videos(id) on delete set null;

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

    -- Human-visible messages raise a new_message notification. System messages
    -- already carry their own offer_* notification from the workflow RPCs.
    if new.kind in ('text', 'dream_share') then
        insert into notifications (user_id, type, actor_id, conversation_id, dream_id, preview)
        select cp.user_id, 'new_message', new.sender_id, new.conversation_id,
               coalesce(new.shared_dream_id, c.dream_id), left(new.body, 140)
        from conversation_participants cp
        join conversations c on c.id = cp.conversation_id
        where cp.conversation_id = new.conversation_id
          and cp.user_id <> new.sender_id;
    end if;

    return new;
end;
$$;

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

    -- Reuse an existing direct 1:1 chat between these users. Help-offer chats
    -- keep their dream_id, so they remain separate collaboration threads.
    select c.id into v_conv
    from conversations c
    join conversation_participants me
      on me.conversation_id = c.id and me.user_id = v_caller
    join conversation_participants them
      on them.conversation_id = c.id and them.user_id = p_recipient_id
    where c.dream_id is null
      and (
          select count(*)
          from conversation_participants cp
          where cp.conversation_id = c.id
      ) = 2
    order by coalesce(c.last_message_at, c.created_at) desc
    limit 1;

    if v_conv is null then
        insert into conversations (dream_id) values (null) returning id into v_conv;

        insert into conversation_participants (conversation_id, user_id, role)
        values (v_conv, v_caller, 'member'), (v_conv, p_recipient_id, 'member');
    end if;

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

revoke execute on function share_dream_video(uuid, uuid, uuid, text) from public;
revoke execute on function share_dream_video(uuid, uuid, uuid, text) from anon;
grant execute on function share_dream_video(uuid, uuid, uuid, text) to authenticated;

-- Trigger-only function; it should not be exposed through /rpc.
revoke execute on function on_message_insert() from public;
revoke execute on function on_message_insert() from anon;
revoke execute on function on_message_insert() from authenticated;
