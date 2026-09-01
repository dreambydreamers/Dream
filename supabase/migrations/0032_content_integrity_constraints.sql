-- 0032_content_integrity_constraints.sql
-- Production-readiness audit (2026-08): input validation + thread integrity.
--
-- Two gaps this closes:
--
--  1. Thread integrity. A client controls both `dream_id` and `video_id`/
--     `photo_id` when inserting a comment or a like, and nothing checked that
--     the clip actually belongs to the dream. Since the thread key is
--     coalesce(video_id, photo_id, dream_id), an attacker could post with
--     dream_id = their own dream and video_id = someone else's clip: the row
--     lands in the victim's thread, while the delete policy grants moderation
--     to the owner of `dream_id` — the attacker. The victim could not remove it.
--
--  2. Length limits. Only dream_comments.body had one. Every other
--     user-writable column was unbounded `text`, so a scripted client holding
--     the publishable key could write multi-megabyte titles, bios and messages.
--     Limits below are sized well above anything the UI can produce (the
--     largest live value at time of writing is a 75-char dream description).
--
-- Also constrains profiles.avatar_url, which is self-updatable free text that
-- every viewer's client loads as an image: an arbitrary host there beacons the
-- IP of everyone who sees that user's card, comment or DM.

-- =========================================================
-- 1. Comment / like threads must belong to their dream.
-- =========================================================
-- A plain CHECK cannot subquery, so this is a trigger. Both fire only when a
-- media id is present, so the gradient-card path costs nothing. Two functions
-- rather than one because dream_likes has no photo_id column, and plpgsql
-- resolves record fields at plan time — a shared body referencing new.photo_id
-- would fail on every like.

create or replace function public.assert_comment_thread_belongs_to_dream()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if new.video_id is not null
       and not exists (
           select 1 from public.dream_videos v
           where v.id = new.video_id and v.dream_id = new.dream_id
       )
    then
        raise exception 'video % does not belong to dream %', new.video_id, new.dream_id
            using errcode = '23514';
    end if;

    if new.photo_id is not null
       and not exists (
           select 1 from public.dream_photo_updates p
           where p.id = new.photo_id and p.dream_id = new.dream_id
       )
    then
        raise exception 'photo % does not belong to dream %', new.photo_id, new.dream_id
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create or replace function public.assert_like_thread_belongs_to_dream()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if new.video_id is not null
       and not exists (
           select 1 from public.dream_videos v
           where v.id = new.video_id and v.dream_id = new.dream_id
       )
    then
        raise exception 'video % does not belong to dream %', new.video_id, new.dream_id
            using errcode = '23514';
    end if;

    return new;
end;
$$;

revoke execute on function public.assert_comment_thread_belongs_to_dream() from public, anon, authenticated;
revoke execute on function public.assert_like_thread_belongs_to_dream()    from public, anon, authenticated;

drop trigger if exists dream_comments_thread_integrity on public.dream_comments;
create trigger dream_comments_thread_integrity
    before insert or update on public.dream_comments
    for each row
    execute function public.assert_comment_thread_belongs_to_dream();

drop trigger if exists dream_likes_thread_integrity on public.dream_likes;
create trigger dream_likes_thread_integrity
    before insert or update on public.dream_likes
    for each row
    execute function public.assert_like_thread_belongs_to_dream();

-- =========================================================
-- 2. Length / cardinality limits on user-writable content.
-- =========================================================

alter table public.dreams
    drop constraint if exists dreams_title_len,
    add  constraint dreams_title_len       check (char_length(title) <= 200),
    drop constraint if exists dreams_description_len,
    add  constraint dreams_description_len check (char_length(description) <= 5000),
    drop constraint if exists dreams_location_len,
    add  constraint dreams_location_len    check (location is null or char_length(location) <= 120),
    drop constraint if exists dreams_help_tags_count,
    add  constraint dreams_help_tags_count check (coalesce(array_length(help_tags, 1), 0) <= 20);

alter table public.profiles
    drop constraint if exists profiles_name_len,
    add  constraint profiles_name_len     check (name is null or char_length(name) <= 80),
    drop constraint if exists profiles_location_len,
    add  constraint profiles_location_len check (location is null or char_length(location) <= 120),
    drop constraint if exists profiles_skills_count,
    add  constraint profiles_skills_count check (coalesce(array_length(skills, 1), 0) <= 30),
    -- Handles appear as @mentions across the app; keep them to a predictable
    -- shape so they cannot impersonate other UI or carry control characters.
    drop constraint if exists profiles_handle_format,
    add  constraint profiles_handle_format
        check (handle is null or handle ~ '^[a-zA-Z0-9_.]{2,30}$'),
    -- Avatars must live in our own public storage. See the header note.
    drop constraint if exists profiles_avatar_url_origin,
    add  constraint profiles_avatar_url_origin
        check (
            avatar_url is null
            or avatar_url like 'https://ohmtchfldrqobwrtyhmz.supabase.co/storage/v1/object/public/%'
        );

alter table public.messages
    drop constraint if exists messages_body_len,
    add  constraint messages_body_len check (char_length(body) <= 5000);

alter table public.dream_videos
    drop constraint if exists dream_videos_title_len,
    add  constraint dream_videos_title_len   check (title is null or char_length(title) <= 200),
    drop constraint if exists dream_videos_caption_len,
    add  constraint dream_videos_caption_len check (caption is null or char_length(caption) <= 2000);

alter table public.dream_photo_updates
    drop constraint if exists dream_photo_updates_title_len,
    add  constraint dream_photo_updates_title_len   check (char_length(title) <= 200),
    drop constraint if exists dream_photo_updates_caption_len,
    add  constraint dream_photo_updates_caption_len check (caption is null or char_length(caption) <= 2000);

alter table public.help_offers
    drop constraint if exists help_offers_skill_len,
    add  constraint help_offers_skill_len   check (char_length(skill) <= 120),
    drop constraint if exists help_offers_message_len,
    add  constraint help_offers_message_len check (char_length(message) <= 2000);

alter table public.journey_steps
    drop constraint if exists journey_steps_note_len,
    add  constraint journey_steps_note_len       check (char_length(note) <= 2000),
    drop constraint if exists journey_steps_date_label_len,
    add  constraint journey_steps_date_label_len check (char_length(date_label) <= 60),
    drop constraint if exists journey_steps_stage_len,
    add  constraint journey_steps_stage_len      check (char_length(stage) <= 60);
