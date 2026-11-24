-- =====================================================================
-- CP4: monthly RANGE partitioning design for viewing activity
--
-- This is a side-by-side copy; the original netflix.viewing_activity
-- remains unchanged for CP1/CP3 comparisons.
-- Run after schema, data load, and optional CP3 indexes:
--   psql -d netflix_large -v ON_ERROR_STOP=1 -f sql/08_partitioning.sql
--
-- Partition key: started_at (TIMESTAMPTZ), monthly ranges aligned to
-- Asia/Kolkata midnight boundaries. Partitions cover Jan-2025 through
-- Dec-2027; DEFAULT catches out-of-range timestamps.
--
-- The partitioned primary key includes started_at as PostgreSQL requires.
-- PRIMARY KEY (view_id, started_at) does not enforce global uniqueness of
-- view_id. A production cutover needs a global ID allocator or registry.
-- =====================================================================

SET search_path TO netflix;

-- IF NOT EXISTS does not migrate an older copy. Inspect/rebuild an existing
-- partitioned copy before relying on this corrected table definition.
CREATE TABLE IF NOT EXISTS viewing_activity_partitioned (
    view_id INTEGER NOT NULL,
    profile_id INTEGER NOT NULL,
    title_id INTEGER NOT NULL,
    episode_id INTEGER,
    started_at TIMESTAMPTZ NOT NULL,
    duration_watched_sec INTEGER NOT NULL
        CHECK (duration_watched_sec >= 0),
    device_type VARCHAR(10) NOT NULL,
    completed BOOLEAN NOT NULL,
    CONSTRAINT fk_viewing_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles(profile_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_viewing_title
        FOREIGN KEY (title_id)
        REFERENCES titles(title_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_viewing_episode_title
        FOREIGN KEY (episode_id, title_id)
        REFERENCES episodes(episode_id, title_id)
        MATCH SIMPLE
        ON DELETE RESTRICT,
    CONSTRAINT viewing_activity_partitioned_pkey
        PRIMARY KEY (view_id, started_at)
) PARTITION BY RANGE (started_at);

COMMENT ON TABLE viewing_activity_partitioned IS
'Monthly partitioned side-by-side copy; original viewing_activity remains unchanged.';

COMMENT ON CONSTRAINT viewing_activity_partitioned_pkey
ON viewing_activity_partitioned IS
'Partition key started_at is required; this key does not guarantee global uniqueness of view_id alone.';

-- Create monthly partitions from January 2025 through December 2027.
DO $partition_setup$
DECLARE
    month_start DATE := DATE '2025-01-01';
    month_end DATE;
    lower_bound TIMESTAMPTZ;
    upper_bound TIMESTAMPTZ;
    partition_name TEXT;
BEGIN
    WHILE month_start < DATE '2028-01-01' LOOP
        month_end := (month_start + INTERVAL '1 month')::DATE;
        lower_bound := month_start::TIMESTAMP AT TIME ZONE 'Asia/Kolkata';
        upper_bound := month_end::TIMESTAMP AT TIME ZONE 'Asia/Kolkata';
        partition_name := 'viewing_activity_p' || TO_CHAR(month_start, 'YYYYMM');

        IF TO_REGCLASS('netflix.' || partition_name) IS NULL THEN
            EXECUTE FORMAT(
                'CREATE TABLE netflix.%I PARTITION OF netflix.viewing_activity_partitioned
                 FOR VALUES FROM (%L) TO (%L)',
                partition_name, lower_bound, upper_bound
            );
        END IF;
        month_start := month_end;
    END LOOP;
END
$partition_setup$;

CREATE TABLE IF NOT EXISTS viewing_activity_p_default
    PARTITION OF viewing_activity_partitioned DEFAULT;

-- Copy the original rows. Re-running is safe for rows already copied.
INSERT INTO viewing_activity_partitioned (
    view_id, profile_id, title_id, episode_id, started_at,
    duration_watched_sec, device_type, completed
)
SELECT view_id, profile_id, title_id, episode_id, started_at,
       duration_watched_sec, device_type, completed
FROM viewing_activity
ON CONFLICT (view_id, started_at) DO NOTHING;

-- Partition-aware indexes aligned with the CP3 activity access paths.
CREATE INDEX IF NOT EXISTS viewing_activity_part_profile_unfinished_idx
    ON viewing_activity_partitioned (profile_id, title_id, started_at DESC)
    INCLUDE (episode_id, duration_watched_sec)
    WHERE NOT completed;

CREATE INDEX IF NOT EXISTS viewing_activity_part_profile_started_idx
    ON viewing_activity_partitioned (profile_id, started_at DESC)
    INCLUDE (title_id, episode_id, duration_watched_sec, completed);

CREATE INDEX IF NOT EXISTS viewing_activity_part_title_started_idx
    ON viewing_activity_partitioned (title_id, started_at DESC);

CREATE INDEX IF NOT EXISTS viewing_activity_part_episode_idx
    ON viewing_activity_partitioned (episode_id)
    WHERE episode_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS viewing_activity_part_started_idx
    ON viewing_activity_partitioned (started_at DESC);

-- Optional BRIN for broad time scans within physically ordered partitions.
-- Keep only if measured plans show a benefit.
CREATE INDEX IF NOT EXISTS viewing_activity_part_started_brin_idx
    ON viewing_activity_partitioned USING BRIN (started_at)
    WITH (pages_per_range = 64);

ANALYZE viewing_activity_partitioned;

-- Row count and full-row equivalence checks; both EXCEPT counts should be 0.
SELECT (SELECT COUNT(*) FROM viewing_activity) AS original_rows,
       (SELECT COUNT(*) FROM viewing_activity_partitioned) AS partitioned_rows;

SELECT COUNT(*) AS rows_missing_from_partitioned
FROM (
    SELECT view_id, profile_id, title_id, episode_id, started_at,
           duration_watched_sec, device_type, completed
    FROM viewing_activity
    EXCEPT ALL
    SELECT view_id, profile_id, title_id, episode_id, started_at,
           duration_watched_sec, device_type, completed
    FROM viewing_activity_partitioned
) AS missing_rows;

SELECT COUNT(*) AS extra_rows_in_partitioned
FROM (
    SELECT view_id, profile_id, title_id, episode_id, started_at,
           duration_watched_sec, device_type, completed
    FROM viewing_activity_partitioned
    EXCEPT ALL
    SELECT view_id, profile_id, title_id, episode_id, started_at,
           duration_watched_sec, device_type, completed
    FROM viewing_activity
) AS extra_rows;

-- Inspect the plan and verify that only the June 2026 partition is scanned.
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM viewing_activity_partitioned
WHERE started_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND started_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30';

SELECT child.relname AS partition_name,
       pg_size_pretty(pg_total_relation_size(child.oid)) AS total_size,
       pg_total_relation_size(child.oid) AS total_size_bytes
FROM pg_inherits i
JOIN pg_class parent ON parent.oid = i.inhparent
JOIN pg_class child ON child.oid = i.inhrelid
JOIN pg_namespace n ON n.oid = parent.relnamespace
WHERE n.nspname = 'netflix'
  AND parent.relname = 'viewing_activity_partitioned'
ORDER BY child.relname;

-- This script has not been run in the current workspace environment.
-- Preserve the row-count, EXCEPT, and EXPLAIN outputs as project evidence.
