-- Fairness report for the recommendation system. Read-only.
--
-- Run each section separately (psql \i works too). The system's success
-- metric is successful connections; these queries surface the failure mode
-- that matters most: dreams aging without offers or exposure.

-- ---------------------------------------------------------------------------
-- 1. Per-dream exposure & offers (most-starved first)
-- ---------------------------------------------------------------------------
select
    d.id,
    d.title,
    d.category,
    d.stage,
    extract(day from now() - d.created_at)::int as age_days,
    coalesce(c.impressions, 0)                  as impressions,
    coalesce(c.distinct_viewers, 0)             as distinct_viewers,
    coalesce(c.offers_received, 0)              as offers_received,
    (
        select count(*)
        from dream_seen s
        where s.dream_id = d.id
          and s.first_seen_at < d.created_at + interval '7 days'
    ) as viewers_in_first_7_days
from dreams d
left join dream_exposure_counters c on c.dream_id = d.id
order by coalesce(c.offers_received, 0) asc,
         coalesce(c.distinct_viewers, 0) asc,
         age_days desc;

-- ---------------------------------------------------------------------------
-- 2. Headline fairness numbers
--    * share of dreams >= 30 days old with ZERO offers (the metric the
--      algorithm is judged on — drive this down)
--    * share of >= 7-day-old dreams that met the 7-day exposure floor
-- ---------------------------------------------------------------------------
select
    count(*) filter (where age_days >= 30)                                   as dreams_30d_plus,
    count(*) filter (where age_days >= 30 and offers_received = 0)           as zero_offer_30d_plus,
    round(100.0 * count(*) filter (where age_days >= 30 and offers_received = 0)
        / nullif(count(*) filter (where age_days >= 30), 0), 1)              as pct_zero_offers_after_30d,
    count(*) filter (where age_days >= 7)                                    as dreams_7d_plus,
    count(*) filter (where age_days >= 7 and viewers_first_week >= 25)       as met_exposure_floor,
    round(100.0 * count(*) filter (where age_days >= 7 and viewers_first_week >= 25)
        / nullif(count(*) filter (where age_days >= 7), 0), 1)               as pct_met_7d_floor
from (
    select
        d.id,
        extract(day from now() - d.created_at)::int as age_days,
        coalesce(c.offers_received, 0) as offers_received,
        (
            select count(*)
            from dream_seen s
            where s.dream_id = d.id
              and s.first_seen_at < d.created_at + interval '7 days'
        ) as viewers_first_week
    from dreams d
    left join dream_exposure_counters c on c.dream_id = d.id
) per_dream;

-- ---------------------------------------------------------------------------
-- 3. Impression spread by category (p10 / p50 / p90) — watch for categories
--    the feed systematically under-serves
-- ---------------------------------------------------------------------------
select
    d.category,
    count(*) as dreams,
    percentile_cont(0.1) within group (order by coalesce(c.impressions, 0)) as p10_impressions,
    percentile_cont(0.5) within group (order by coalesce(c.impressions, 0)) as p50_impressions,
    percentile_cont(0.9) within group (order by coalesce(c.impressions, 0)) as p90_impressions,
    sum(coalesce(c.offers_received, 0)) as total_offers
from dreams d
left join dream_exposure_counters c on c.dream_id = d.id
group by d.category
order by p50_impressions asc;

-- ---------------------------------------------------------------------------
-- 4. Connection funnel: offer_sent -> accepted -> conversation -> delivered.
--    Conversion drops tell you whether the matches were real.
-- ---------------------------------------------------------------------------
select
    count(*)                                                    as offers_sent,
    count(*) filter (where accepted_at is not null)             as accepted,
    count(*) filter (where conversation_id is not null)         as with_conversation,
    count(*) filter (where completed_at is not null)            as support_delivered,
    round(100.0 * count(*) filter (where accepted_at is not null) / nullif(count(*), 0), 1)  as pct_accepted,
    round(100.0 * count(*) filter (where completed_at is not null) / nullif(count(*), 0), 1) as pct_delivered
from help_offers;

-- ---------------------------------------------------------------------------
-- 5. Median time-to-first-offer by posting week — is matching getting faster?
-- ---------------------------------------------------------------------------
select
    date_trunc('week', d.created_at)::date as posted_week,
    count(distinct d.id) as dreams,
    percentile_cont(0.5) within group (
        order by extract(epoch from first_offer.at - d.created_at) / 86400.0
    ) as median_days_to_first_offer
from dreams d
join lateral (
    select min(o.created_at) as at
    from help_offers o
    where o.dream_id = d.id
) first_offer on first_offer.at is not null
group by 1
order by 1;
