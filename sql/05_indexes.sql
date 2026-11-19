-- =====================================================================
-- Netflix — CP3: index set for the optimized workload
--
-- Index choices follow the baseline plans in
-- benchmarks/results/baseline/summary.csv and the matching raw plan files.
-- Confirm actual use and write overhead in the optimized benchmark.
-- =====================================================================

BEGIN;

SET search_path TO netflix;

-- R05: trigram matching supports the leading-wildcard title search.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- viewing_activity (200,401 rows)

-- R01: unfinished rows for one profile, ordered by title and newest view.
CREATE INDEX viewing_activity_profile_unfinished_idx
    ON viewing_activity (profile_id, title_id, started_at DESC)
    INCLUDE (episode_id, duration_watched_sec)
    WHERE NOT completed;

-- R14: profile-driven probes after identifying kids profiles.
CREATE INDEX viewing_activity_profile_started_idx
    ON viewing_activity (profile_id, started_at DESC)
    INCLUDE (title_id, episode_id, duration_watched_sec, completed);

-- R19: title-specific count and latest-view subqueries.
CREATE INDEX viewing_activity_title_started_idx
    ON viewing_activity (title_id, started_at DESC);

-- R13: anti-join by episode; movie views with NULL episode IDs are omitted.
CREATE INDEX viewing_activity_episode_idx
    ON viewing_activity (episode_id)
    WHERE episode_id IS NOT NULL;

-- R03, R08, R09, R18, R23: time ranges and newest-first ordering.
CREATE INDEX viewing_activity_started_idx
    ON viewing_activity (started_at DESC);

-- titles (3,000 rows)

-- R04: maturity filter and recent-addition ordering.
CREATE INDEX titles_maturity_added_idx
    ON titles (maturity_rating, added_on DESC);

-- R22: lookup titles with a scheduled leaving date.
CREATE INDEX titles_leaving_idx
    ON titles (leaving_on)
    WHERE leaving_on IS NOT NULL;

-- R05: substring search; a B-tree cannot serve '%text%'.
CREATE INDEX titles_name_trgm_idx
    ON titles USING gin (name gin_trgm_ops);

-- R04, R09, R25: reverse lookup by genre_id (PK begins with title_id).
CREATE INDEX title_genres_genre_idx
    ON title_genres (genre_id, title_id);

-- accounts (25,000 rows)

-- R10: exact expression used by the case-insensitive sign-in predicate.
CREATE INDEX accounts_lower_email_idx
    ON accounts (lower(email));

-- R21 and selective status filters; broad queries may still scan.
CREATE INDEX accounts_status_next_billing_idx
    ON accounts (status, next_billing_date);

-- R12: cancellation dates for cancelled accounts only.
CREATE INDEX accounts_cancelled_idx
    ON accounts (cancelled_on)
    WHERE status = 'CANCELLED';

-- profiles (75,000 rows)

-- R24: one account's profiles ordered by creation time.
CREATE INDEX profiles_account_created_idx
    ON profiles (account_id, created_at);

-- R14: enumerate kids profiles before probing viewing_activity.
CREATE INDEX profiles_kids_idx
    ON profiles (profile_id)
    WHERE is_kids;

-- invoices (133,057 rows)

-- R11: failed invoice search by status and billing period.
CREATE INDEX invoices_status_period_idx
    ON invoices (status, billing_period_start)
    INCLUDE (account_id, amount_inr);

-- W05: correlated EXISTS lookup begins with account_id.
CREATE INDEX invoices_account_period_status_idx
    ON invoices (account_id, billing_period_start, status);

-- my_list (59,992 rows)

-- R06: one profile's list in most-recently-added order.
CREATE INDEX my_list_profile_added_idx
    ON my_list (profile_id, added_at DESC)
    INCLUDE (title_id);

-- R20: additions in a date window, grouped by title.
CREATE INDEX my_list_added_title_idx
    ON my_list (added_at, title_id);

-- R17 aggregates all ratings; the baseline sequential scan is appropriate.

COMMIT;
