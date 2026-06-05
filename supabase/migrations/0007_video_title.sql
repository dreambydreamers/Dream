-- Per-video heading. Lets "update" clips carry their own title in the feed,
-- distinct from the parent dream's title. Null for the original cover video.
alter table dream_videos add column if not exists title text;
