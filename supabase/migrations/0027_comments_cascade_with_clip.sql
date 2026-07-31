-- A clip's comment thread dies with the clip: deleting a dream_videos row now
-- cascade-deletes its comments instead of orphaning them onto the dream-level
-- thread (previous behavior: on delete set null). Dream-level comments
-- (video_id null, videoless dreams) are unaffected.

alter table public.dream_comments
    drop constraint dream_comments_video_id_fkey;

alter table public.dream_comments
    add constraint dream_comments_video_id_fkey
    foreign key (video_id) references public.dream_videos(id) on delete cascade;
