-- Seed data for inspecting the recommendation feed with realistic variety.
--
-- *** LOCAL DEVELOPMENT ONLY ***
-- This file inserts rows directly into auth.users, which is only valid on a
-- local stack (`supabase db reset` applies migrations, then this file) or a
-- disposable preview branch. For a hosted project, create users through the
-- service-role admin API instead. A guard below refuses to run against a
-- database that already contains non-seed users.
--
-- What it creates:
--   * 30 users (supporter01@seed.dream.local … , password 'password123'),
--     each with profile skills/location and a supporter capability profile.
--   * 60 dreams in four cohorts:
--       1–10   "popular"  — 20–40 days old, several help offers, high exposure
--       11–40  "mid"      — 3–25 days old, moderate exposure, a few offers
--       41–55  "starved"  — 31–45 days old, ZERO offers, minimal exposure
--       56–60  "fresh"    — < 36 hours old, no exposure yet
--   * Skewed help offers (popular cohort only), varied statuses for the funnel.
--   * dream_seen + engagement_events shaped to match, with exposure counters
--     recomputed at the end.
--
-- Inspect afterwards with supabase/queries/fairness_report.sql, or sign in as
-- any seed user in the app and pull ranked candidates.

do $$
begin
    if coalesce(current_setting('dream.seed_force', true), '') <> 'on'
       and exists (select 1 from auth.users where email not like '%@seed.dream.local') then
        raise exception 'seed.sql refused to run: this database contains non-seed users (hosted project?). Use a local stack or preview branch.';
    end if;
end $$;

do $$
declare
    all_types public.help_type[] :=
        array['code','design','funding','mentorship','marketing','legal','space','other']::public.help_type[];
    all_categories text[] :=
        array['tech','food','art','impact','education','health','music','sport'];
    all_stages text[] := array['idea','early','needs','almost'];
    locations text[] := array['Zagreb','Berlin','London','Remote'];
    tag_combos text[] := array[
        'Coding|Design', 'Funding', 'Mentorship|Marketing', 'Legal',
        'Space', 'Coding|Funding', 'Design|Marketing', 'Coding'
    ];
    n int;
    d int;
    v int;
    owner_n int;
    helper_n int;
    viewer_n int;
    offers_n int;
    viewer_count int;
    u uuid;
    sd_id uuid;
    dream_created timestamptz;
    first_seen timestamptz;
    status public.help_offer_status;
begin
    -- ---- 1. Users (auth trigger creates the profiles) -----------------------
    for n in 1..30 loop
        u := ('00000000-0000-4000-a000-' || lpad(n::text, 12, '0'))::uuid;

        insert into auth.users
            (id, instance_id, aud, role, email, encrypted_password,
             email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
             created_at, updated_at)
        values
            (u, '00000000-0000-0000-0000-000000000000',
             'authenticated', 'authenticated',
             format('supporter%s@seed.dream.local', lpad(n::text, 2, '0')),
             extensions.crypt('password123', extensions.gen_salt('bf')),
             now() - interval '60 days',
             '{"provider":"email","providers":["email"]}'::jsonb,
             jsonb_build_object(
                 'name', format('Seed User %s', n),
                 'handle', format('seed_user%s', lpad(n::text, 2, '0'))),
             now() - interval '60 days', now() - interval '60 days')
        on conflict (id) do nothing;

        insert into auth.identities
            (id, user_id, provider_id, identity_data, provider,
             last_sign_in_at, created_at, updated_at)
        values
            (gen_random_uuid(), u, u::text,
             jsonb_build_object('sub', u::text,
                 'email', format('supporter%s@seed.dream.local', lpad(n::text, 2, '0'))),
             'email', now(), now(), now())
        on conflict do nothing;

        -- Profile skills/location (profile row was created by handle_new_user).
        update public.profiles set
            skills = case (n % 6)
                when 0 then array['iOS development', 'design']
                when 1 then array['funding', 'investment']
                when 2 then array['marketing', 'photography']
                when 3 then array['mentorship', 'networking']
                when 4 then array['legal']
                else array['coding', 'cooking'] end,
            location = case when n % 5 = 0 then null else locations[(n % 4) + 1] end
        where id = u;

        -- Supporter capability profile: 3 help types round-robin so every
        -- type has ~11 potential helpers.
        insert into public.supporter_profiles
            (user_id, help_types, weekly_capacity_hours,
             categories_of_interest, preferred_stages)
        values
            (u,
             array[all_types[(n % 8) + 1],
                   all_types[((n + 1) % 8) + 1],
                   all_types[((n + 2) % 8) + 1]],
             (n % 10) + 1,
             array[all_categories[(n % 8) + 1]]::public.dream_category[],
             case (n % 3)
                 when 0 then array['idea','early']::public.dream_stage[]
                 when 1 then array['needs']::public.dream_stage[]
                 else '{}'::public.dream_stage[] end)
        on conflict (user_id) do nothing;
    end loop;

    -- ---- 2. Dreams in four cohorts ------------------------------------------
    for d in 1..60 loop
        owner_n := ((d - 1) % 20) + 1;
        sd_id := ('00000000-0000-4000-b000-' || lpad(d::text, 12, '0'))::uuid;
        dream_created := case
            when d <= 10 then now() - make_interval(days => 20 + (d * 2))       -- popular: 22–40d
            when d <= 40 then now() - make_interval(days => 3 + (d % 23))       -- mid: 3–25d
            when d <= 55 then now() - make_interval(days => 31 + (d % 15))      -- starved: 31–45d
            else now() - make_interval(hours => 4 + (d % 32))                   -- fresh: < 36h
        end;

        insert into public.dreams
            (id, owner_id, title, description, category, stage, location,
             help_tags, created_at)
        values
            (sd_id,
             ('00000000-0000-4000-a000-' || lpad(owner_n::text, 12, '0'))::uuid,
             format('Seed dream %s (%s)', d, all_categories[(d % 8) + 1]),
             format('A %s-stage %s dream from the seed data set.',
                    all_stages[(d % 4) + 1], all_categories[(d % 8) + 1]),
             all_categories[(d % 8) + 1]::public.dream_category,
             all_stages[(d % 4) + 1]::public.dream_stage,
             case when d % 5 = 0 then null else locations[(d % 4) + 1] end,
             string_to_array(tag_combos[(d % 8) + 1], '|'),
             dream_created)
        on conflict (id) do nothing;
    end loop;

    -- ---- 3. Help offers: popular cohort soaks up almost all of them ---------
    for d in 1..25 loop
        if d <= 10 then
            offers_n := 2 + (d % 5);          -- popular: 2–6 offers
        elsif d % 3 = 0 then
            offers_n := 1;                    -- a few mid dreams: 1 offer
        else
            continue;
        end if;

        owner_n := ((d - 1) % 20) + 1;
        sd_id := ('00000000-0000-4000-b000-' || lpad(d::text, 12, '0'))::uuid;
        select created_at into dream_created from public.dreams where id = sd_id;

        for v in 1..offers_n loop
            helper_n := ((d + v * 3) % 30) + 1;
            if helper_n = owner_n then
                helper_n := (helper_n % 30) + 1;
            end if;
            status := (array['pending','accepted','in_progress','completed','rejected'])[(v % 5) + 1]::public.help_offer_status;

            insert into public.help_offers
                (dream_id, supporter_id, skill, message, status, created_at, updated_at)
            values
                (sd_id,
                 ('00000000-0000-4000-a000-' || lpad(helper_n::text, 12, '0'))::uuid,
                 (select ht[1] from (select help_tags as ht from public.dreams where id = sd_id) t),
                 'Seed offer — happy to help with this.',
                 status,
                 dream_created + make_interval(days => v),
                 dream_created + make_interval(days => v))
            on conflict do nothing;
        end loop;
    end loop;

    -- ---- 4. Views / engagement shaped per cohort ----------------------------
    for d in 1..60 loop
        viewer_count := case
            when d <= 10 then 25                  -- popular: broad reach
            when d <= 40 then 6 + (d % 10)        -- mid: moderate reach
            when d <= 55 then d % 3               -- starved: 0–2 viewers
            else 0                                 -- fresh: none yet
        end;
        if viewer_count = 0 then
            continue;
        end if;

        owner_n := ((d - 1) % 20) + 1;
        sd_id := ('00000000-0000-4000-b000-' || lpad(d::text, 12, '0'))::uuid;
        select created_at into dream_created from public.dreams where id = sd_id;

        for v in 1..viewer_count loop
            viewer_n := ((d * 7 + v * 11) % 30) + 1;
            if viewer_n = owner_n then
                viewer_n := (viewer_n % 30) + 1;
            end if;
            u := ('00000000-0000-4000-a000-' || lpad(viewer_n::text, 12, '0'))::uuid;
            first_seen := least(dream_created + make_interval(days => (v % 5) + 1), now());

            insert into public.dream_seen as ds
                (user_id, dream_id, first_seen_at, last_seen_at, seen_count)
            values (u, sd_id, first_seen, first_seen, 1)
            on conflict (user_id, dream_id) do update
                set seen_count = ds.seen_count + 1;

            insert into public.engagement_events
                (user_id, dream_id, event_type, watch_ms, video_duration_ms, created_at)
            values (u, sd_id, 'view', null, null, first_seen);

            case (d + v) % 4
                when 0 then
                    insert into public.engagement_events
                        (user_id, dream_id, event_type, watch_ms, video_duration_ms, created_at)
                    values (u, sd_id, 'watch_progress', 12000, 20000, first_seen);
                when 1 then
                    insert into public.engagement_events
                        (user_id, dream_id, event_type, watch_ms, video_duration_ms, created_at)
                    values (u, sd_id, 'complete', 20000, 20000, first_seen);
                when 2 then
                    insert into public.engagement_events
                        (user_id, dream_id, event_type, watch_ms, video_duration_ms, created_at)
                    values (u, sd_id, 'skip', 1200, 20000, first_seen);
                else
                    null;
            end case;
        end loop;
    end loop;

    -- ---- 5. Recompute exposure counters from the seeded seen-set ------------
    -- (offers_received was already maintained by the help_offers trigger.)
    update public.dream_exposure_counters c
    set impressions = s.imp,
        distinct_viewers = s.dv,
        last_impression_at = s.last_seen
    from (
        select dream_id as sd, sum(seen_count)::bigint as imp,
               count(*)::bigint as dv, max(last_seen_at) as last_seen
        from public.dream_seen
        group by dream_id
    ) s
    where c.dream_id = s.sd;

    update public.dreams dr
    set views_count = c.impressions::int
    from public.dream_exposure_counters c
    where c.dream_id = dr.id;
end $$;
