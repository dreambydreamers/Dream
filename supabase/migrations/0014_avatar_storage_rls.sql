-- Avatar overwrite/remove RLS repair.
-- If 0013_profile_avatar.sql was already applied before it gained the narrow
-- SELECT policy, this follow-up keeps existing projects covered. The DO block
-- also makes it safe when 0013 already created the policy.

do $$
begin
    if not exists (
        select 1
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname = 'auth users read own avatar'
    ) then
        create policy "auth users read own avatar"
        on storage.objects for select
        using (
            bucket_id = 'avatars'
            and auth.role() = 'authenticated'
            and (storage.foldername(name))[1] = auth.uid()::text
        );
    end if;
end $$;

alter policy "auth users update own avatar"
on storage.objects
using (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
);
