-- Adds the 'like' engagement event, split from 0028 because
-- `ALTER TYPE ... ADD VALUE` is the one statement that can fail inside a
-- transaction block depending on how the migration runner wraps it.
--
-- This feeds ONLY the liking viewer's own affinity profile. The per-dream like
-- count comes from dream_likes / dream_like_counts, never from here — see the
-- invariant at the top of 0022_engagement.sql.

alter type public.engagement_event_type add value if not exists 'like';
