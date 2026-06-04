-- Populate profile fields from sign-up metadata.
-- The email/password sign-up flow passes `name` and `handle` in the user's
-- raw_user_meta_data; read them here so a profile is created complete instead
-- of with null handle/name. Falls back to the email local-part for handle.

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    meta_name   text := nullif(trim(new.raw_user_meta_data ->> 'name'), '');
    meta_handle text := nullif(trim(new.raw_user_meta_data ->> 'handle'), '');
    fallback    text := nullif(split_part(coalesce(new.email, ''), '@', 1), '');
    want_handle text := coalesce(meta_handle, fallback);
begin
    -- handle is UNIQUE; drop it rather than abort the signup if it's taken.
    if want_handle is not null
       and exists (select 1 from public.profiles where handle = want_handle) then
        want_handle := null;
    end if;

    insert into public.profiles (id, name, handle)
    values (new.id, meta_name, want_handle)
    on conflict (id) do nothing;
    return new;
end;
$$;
