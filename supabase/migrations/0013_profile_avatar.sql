-- Profile pictures: a real uploaded avatar image (public `avatars` bucket).
-- `avatar_url` holds the full public URL (with a cache-busting query) of the
-- uploaded image, or null when the user has none (falls back to the procedural
-- seed-gradient avatar). Run after 0012_revoke_anon_messaging_functions.sql.

alter table profiles add column if not exists avatar_url text;

-- The avatars bucket already has insert/update policies (0002_storage.sql) but
-- 0003_harden drops the broad public SELECT policy. Public URLs still work, but
-- Storage update/delete operations need the owner to be able to see their own
-- object row. Without this, replacing/removing an existing avatar can fail RLS.
create policy "auth users read own avatar"
on storage.objects for select
using (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);

-- "Remove photo" needs to delete the stored object.
create policy "auth users delete own avatar"
on storage.objects for delete
using (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);
