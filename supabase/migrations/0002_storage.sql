-- Storage buckets for Dream
-- Run after 0001_init.sql

-- dream-videos: private; readable via signed URLs only
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'dream-videos', 'dream-videos', false,
    524288000, -- 500 MB
    array['video/mp4', 'video/quicktime', 'video/x-m4v']
)
on conflict (id) do nothing;

-- dream-posters: public; thumbnails shown in feed
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'dream-posters', 'dream-posters', true,
    5242880, -- 5 MB
    array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- avatars: public
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'avatars', 'avatars', true,
    2097152, -- 2 MB
    array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- Object paths are namespaced by user id as the first folder, e.g. "{user_id}/{dream_id}/{video_id}.mp4"
-- This lets RLS use storage.foldername(name)[1] = auth.uid()::text

-- ---------- dream-videos policies ----------

create policy "auth users read own videos"
on storage.objects for select
using (
    bucket_id = 'dream-videos'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "auth users upload own videos"
on storage.objects for insert
with check (
    bucket_id = 'dream-videos'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "auth users delete own videos"
on storage.objects for delete
using (
    bucket_id = 'dream-videos'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);

-- ---------- dream-posters policies ----------
-- public bucket; anyone can read, only owner can write

create policy "anyone reads posters"
on storage.objects for select
using (bucket_id = 'dream-posters');

create policy "auth users upload own posters"
on storage.objects for insert
with check (
    bucket_id = 'dream-posters'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "auth users delete own posters"
on storage.objects for delete
using (
    bucket_id = 'dream-posters'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);

-- ---------- avatars policies ----------

create policy "anyone reads avatars"
on storage.objects for select
using (bucket_id = 'avatars');

create policy "auth users manage own avatar"
on storage.objects for insert
with check (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "auth users update own avatar"
on storage.objects for update
using (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);
