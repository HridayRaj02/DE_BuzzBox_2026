-- =============================================================
-- Phase 2: Load seed data into the netflix schema
--
-- Run this after sql/01_schema.sql, from the project root:
--   psql -d <your_database> -f sql/02_load_data.sql
--
-- This file loads the CSV data, updates planner statistics,
-- and runs a few checks to make sure the data is sensible.
--
-- IMPORTANT: first extract seed_data.zip in the project folder.
-- The \copy paths below are relative to where psql is run.
-- =============================================================

SET search_path TO netflix;

-- Load parent tables before child tables so foreign keys work.
-- plans -> accounts -> profiles
-- titles and genres -> title_genres / episodes
-- profiles and titles -> viewing_activity, ratings and my_list
-- accounts -> invoices

\copy plans            FROM 'seed_data/plans.csv'            WITH (FORMAT csv, HEADER true)
\copy accounts         FROM 'seed_data/accounts.csv'         WITH (FORMAT csv, HEADER true)
\copy profiles         FROM 'seed_data/profiles.csv'         WITH (FORMAT csv, HEADER true)
\copy genres           FROM 'seed_data/genres.csv'           WITH (FORMAT csv, HEADER true)
\copy titles           FROM 'seed_data/titles.csv'           WITH (FORMAT csv, HEADER true)
\copy title_genres     FROM 'seed_data/title_genres.csv'     WITH (FORMAT csv, HEADER true)
\copy episodes         FROM 'seed_data/episodes.csv'         WITH (FORMAT csv, HEADER true)
\copy viewing_activity FROM 'seed_data/viewing_activity.csv' WITH (FORMAT csv, HEADER true)
\copy ratings          FROM 'seed_data/ratings.csv'          WITH (FORMAT csv, HEADER true)
\copy my_list          FROM 'seed_data/my_list.csv'          WITH (FORMAT csv, HEADER true)
\copy invoices         FROM 'seed_data/invoices.csv'         WITH (FORMAT csv, HEADER true)

-- Let PostgreSQL collect statistics for the query planner.
ANALYZE plans;
ANALYZE accounts;
ANALYZE profiles;
ANALYZE genres;
ANALYZE titles;
ANALYZE title_genres;
ANALYZE episodes;
ANALYZE viewing_activity;
ANALYZE ratings;
ANALYZE my_list;
ANALYZE invoices;

-- -------------------------------------------------------------
-- Row-count check
-- Expected: plans=4, accounts=25000, profiles=75000, genres=15,
-- titles=3000, title_genres=5963, episodes=20000,
-- viewing_activity=200401, ratings=33900, my_list=59992,
-- invoices=133057.
-- -------------------------------------------------------------
SELECT 'plans' AS tbl, count(*) AS rows FROM plans
UNION ALL SELECT 'accounts', count(*) FROM accounts
UNION ALL SELECT 'profiles', count(*) FROM profiles
UNION ALL SELECT 'genres', count(*) FROM genres
UNION ALL SELECT 'titles', count(*) FROM titles
UNION ALL SELECT 'title_genres', count(*) FROM title_genres
UNION ALL SELECT 'episodes', count(*) FROM episodes
UNION ALL SELECT 'viewing_activity', count(*) FROM viewing_activity
UNION ALL SELECT 'ratings', count(*) FROM ratings
UNION ALL SELECT 'my_list', count(*) FROM my_list
UNION ALL SELECT 'invoices', count(*) FROM invoices
ORDER BY tbl;

-- -------------------------------------------------------------
-- Integrity check 1: a title cannot be watched before it was
-- added to Netflix. Result should be 0.
-- -------------------------------------------------------------
SELECT 'IC1: views before title was added' AS check_name,
count(*) AS violations
FROM viewing_activity v
JOIN titles t ON t.title_id = v.title_id
WHERE v.started_at::date < t.added_on;

-- -------------------------------------------------------------
-- Integrity check 2: when a view is for an episode, the episode
-- must belong to the same series as the title in that view.
-- Result should be 0.
-- -------------------------------------------------------------
SELECT 'IC2: episode and title do not match' AS check_name,
count(*) AS violations
FROM viewing_activity v
JOIN episodes e ON e.episode_id = v.episode_id
WHERE e.title_id <> v.title_id;

-- -------------------------------------------------------------
-- Integrity check 3: an account can have at most five profiles.
-- Result should be 0.
-- -------------------------------------------------------------
SELECT 'IC3: accounts with more than five profiles' AS check_name,
count(*) AS violations
FROM (
    SELECT account_id
    FROM profiles
    GROUP BY account_id
    HAVING count(*) > 5
) AS too_many_profiles;

-- -------------------------------------------------------------
-- Integrity check 4: kids profiles should only have U or UA7 as
-- their maturity setting. Result should be 0.
-- -------------------------------------------------------------
SELECT 'IC4: kids profiles with invalid maturity limit' AS check_name,
count(*) AS violations
FROM profiles
WHERE is_kids = true
AND maturity_limit NOT IN ('U', 'UA7');

-- -------------------------------------------------------------
-- Integrity check 5: paid invoices need a payment timestamp and
-- failed invoices should not have one. Result should be 0.
-- -------------------------------------------------------------
SELECT 'IC5: invoices with invalid payment details' AS check_name,
count(*) AS violations
FROM invoices
WHERE (status IN ('PAID', 'REFUNDED') AND paid_at IS NULL)
OR (status = 'FAILED' AND paid_at IS NOT NULL);
