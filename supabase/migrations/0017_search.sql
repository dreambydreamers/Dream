-- Full-text search on dreams and profiles.
-- dreams: English stemmer on title + description
-- profiles: simple tokeniser (no stemming — better for names/handles)

ALTER TABLE dreams
  ADD COLUMN IF NOT EXISTS fts tsvector
  GENERATED ALWAYS AS (
    to_tsvector('english',
      coalesce(title, '') || ' ' || coalesce(description, '')
    )
  ) STORED;

CREATE INDEX IF NOT EXISTS dreams_fts_idx ON dreams USING GIN(fts);

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS fts tsvector
  GENERATED ALWAYS AS (
    to_tsvector('simple',
      coalesce(handle, '') || ' ' || coalesce(name, '') || ' ' || coalesce(location, '')
    )
  ) STORED;

CREATE INDEX IF NOT EXISTS profiles_fts_idx ON profiles USING GIN(fts);

-- Returns matching dreams joined with owner profile info
CREATE OR REPLACE FUNCTION search_dreams(query text)
RETURNS TABLE (
  id          uuid,
  title       text,
  description text,
  category    text,
  owner_id    uuid,
  owner_name  text,
  owner_handle text,
  avatar_seed  int,
  avatar_url   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    d.id,
    d.title,
    d.description,
    d.category::text,
    d.owner_id,
    p.name        AS owner_name,
    p.handle      AS owner_handle,
    p.avatar_seed,
    p.avatar_url
  FROM dreams d
  LEFT JOIN profiles p ON p.id = d.owner_id
  WHERE d.fts @@ plainto_tsquery('english', query)
  ORDER BY ts_rank(d.fts, plainto_tsquery('english', query)) DESC
  LIMIT 20;
$$;

-- Returns matching profiles
CREATE OR REPLACE FUNCTION search_profiles(query text)
RETURNS TABLE (
  id          uuid,
  name        text,
  handle      text,
  location    text,
  avatar_seed  int,
  avatar_url   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, name, handle, location, avatar_seed, avatar_url
  FROM profiles
  WHERE fts @@ plainto_tsquery('simple', query)
  ORDER BY ts_rank(fts, plainto_tsquery('simple', query)) DESC
  LIMIT 10;
$$;

GRANT EXECUTE ON FUNCTION search_dreams  TO authenticated;
GRANT EXECUTE ON FUNCTION search_profiles TO authenticated;
