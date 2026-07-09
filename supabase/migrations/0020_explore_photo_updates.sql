-- Real mixed-media updates for Explore.
-- Photos are attached to dreams, just like update videos.

alter table public.dream_videos
    add column if not exists caption text;

create table if not exists public.dream_photo_updates (
    id uuid primary key default gen_random_uuid(),
    dream_id uuid not null references public.dreams(id) on delete cascade,
    image_path text not null,
    title text not null,
    caption text,
    width int,
    height int,
    created_at timestamptz not null default now()
);

create index if not exists dream_photo_updates_dream_id_idx
    on public.dream_photo_updates(dream_id);

create index if not exists dream_photo_updates_created_at_idx
    on public.dream_photo_updates(created_at desc);

alter table public.dream_photo_updates enable row level security;

grant select on public.dream_photo_updates to authenticated;
grant insert, update, delete on public.dream_photo_updates to authenticated;

grant select on public.dream_videos to authenticated;
grant insert, update, delete on public.dream_videos to authenticated;

drop policy if exists "dream photo updates are readable by signed-in users"
    on public.dream_photo_updates;
create policy "dream photo updates are readable by signed-in users"
    on public.dream_photo_updates
    for select
    to authenticated
    using (true);

drop policy if exists "dream owners insert photo updates"
    on public.dream_photo_updates;
create policy "dream owners insert photo updates"
    on public.dream_photo_updates
    for insert
    to authenticated
    with check (
        exists (
            select 1
            from public.dreams d
            where d.id = dream_id
              and d.owner_id = (select auth.uid())
        )
    );

drop policy if exists "dream owners delete photo updates"
    on public.dream_photo_updates;
drop policy if exists "dream owners update photo updates"
    on public.dream_photo_updates;
create policy "dream owners update photo updates"
    on public.dream_photo_updates
    for update
    to authenticated
    using (
        exists (
            select 1
            from public.dreams d
            where d.id = dream_id
              and d.owner_id = (select auth.uid())
        )
    )
    with check (
        exists (
            select 1
            from public.dreams d
            where d.id = dream_id
              and d.owner_id = (select auth.uid())
        )
    );

create policy "dream owners delete photo updates"
    on public.dream_photo_updates
    for delete
    to authenticated
    using (
        exists (
            select 1
            from public.dreams d
            where d.id = dream_id
              and d.owner_id = (select auth.uid())
        )
    );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'dream-images', 'dream-images', true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

drop policy if exists "auth users upload own dream images" on storage.objects;
create policy "auth users upload own dream images"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'dream-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "auth users delete own dream images" on storage.objects;
create policy "auth users delete own dream images"
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'dream-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
);
