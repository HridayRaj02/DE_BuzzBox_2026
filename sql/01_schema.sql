-- ============================================================
-- PROJECT: Netflix Movie & Series Streaming Database
-- COURSE: Database Management Systems
-- DATABASE: PostgreSQL 15+
-- FILE: 01_schema.sql
--
-- Purpose:
-- Reconstruct the Netflix database schema using the
-- supplied CSV files and project requirements.
--
-- IMPORTANT:
-- Only constraints are created in this phase.
-- No performance indexes are created manually.
-- ============================================================


-- ============================================================
-- 1. CREATE SCHEMA
-- ============================================================

CREATE SCHEMA IF NOT EXISTS netflix;

SET search_path TO netflix;


-- ============================================================
-- 2. PLANS TABLE
-- ============================================================

CREATE TABLE plans (
    plan_id SMALLINT PRIMARY KEY,

    plan_name VARCHAR(20) NOT NULL UNIQUE,

    monthly_price_inr NUMERIC(8,2) NOT NULL
        CHECK (monthly_price_inr >= 0),

    max_streams SMALLINT NOT NULL
        CHECK (max_streams > 0),

    max_resolution VARCHAR(10) NOT NULL,

    has_ads BOOLEAN NOT NULL
);


-- ============================================================
-- 3. ACCOUNTS TABLE
-- ============================================================

CREATE TABLE accounts (
    account_id INTEGER PRIMARY KEY,

    email VARCHAR(254) NOT NULL UNIQUE,

    phone VARCHAR(15) UNIQUE,

    country_code CHAR(2) NOT NULL
        CHECK (country_code ~ '^[A-Z]{2}$'),

    plan_id SMALLINT NOT NULL,

    signup_date DATE NOT NULL,

    status VARCHAR(10) NOT NULL
        CHECK (status IN ('ACTIVE', 'ON_HOLD', 'CANCELLED')),

    cancelled_on DATE,

    next_billing_date DATE,

    CONSTRAINT fk_accounts_plan
        FOREIGN KEY (plan_id)
        REFERENCES plans(plan_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_account_cancellation
        CHECK (
            (status = 'CANCELLED' AND cancelled_on IS NOT NULL)
            OR
            (status <> 'CANCELLED' AND cancelled_on IS NULL)
        ),

    CONSTRAINT chk_cancellation_date
        CHECK (
            cancelled_on IS NULL
            OR cancelled_on >= signup_date
        ),

    CONSTRAINT chk_next_billing_date
        CHECK (
            next_billing_date IS NULL
            OR next_billing_date >= signup_date
        )
);


-- ============================================================
-- 4. PROFILES TABLE
-- ============================================================

CREATE TABLE profiles (
    profile_id INTEGER PRIMARY KEY,

    account_id INTEGER NOT NULL,

    profile_name VARCHAR(50) NOT NULL,

    is_kids BOOLEAN NOT NULL,

    maturity_limit VARCHAR(5) NOT NULL
        CHECK (
            maturity_limit IN ('U', 'UA7', 'UA13', 'UA16', 'A')
        ),

    language VARCHAR(30) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_profiles_account
        FOREIGN KEY (account_id)
        REFERENCES accounts(account_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_kids_maturity
        CHECK (
            is_kids = FALSE
            OR maturity_limit IN ('U', 'UA7')
        ),

    CONSTRAINT chk_profile_name
        CHECK (LENGTH(TRIM(profile_name)) > 0)
);


-- ============================================================
-- 5. GENRES TABLE
-- ============================================================

CREATE TABLE genres (
    genre_id SMALLINT PRIMARY KEY,

    genre_name VARCHAR(40) NOT NULL UNIQUE
);


-- ============================================================
-- 6. TITLES TABLE
-- ============================================================

CREATE TABLE titles (
    title_id INTEGER PRIMARY KEY,

    title_type VARCHAR(10) NOT NULL
        CHECK (title_type IN ('MOVIE', 'SERIES')),

    name VARCHAR(200) NOT NULL,

    release_year SMALLINT NOT NULL
        CHECK (release_year BETWEEN 1888 AND 2100),

    maturity_rating VARCHAR(5) NOT NULL
        CHECK (
            maturity_rating IN ('U', 'UA7', 'UA13', 'UA16', 'A')
        ),

    original_language VARCHAR(30) NOT NULL,

    runtime_min SMALLINT,

    is_netflix_original BOOLEAN NOT NULL,

    added_on DATE NOT NULL,

    leaving_on DATE,

    CONSTRAINT chk_title_runtime
        CHECK (
            (title_type = 'MOVIE' AND runtime_min IS NOT NULL
                AND runtime_min > 0)
            OR
            (title_type = 'SERIES' AND runtime_min IS NULL)
        ),

    CONSTRAINT chk_title_leaving_date
        CHECK (
            leaving_on IS NULL
            OR leaving_on >= added_on
        ),

    CONSTRAINT chk_original_leaving
        CHECK (
            is_netflix_original = FALSE
            OR leaving_on IS NULL
        ),

    CONSTRAINT chk_title_name
        CHECK (LENGTH(TRIM(name)) > 0)
);


-- ============================================================
-- 7. TITLE_GENRES TABLE
-- ============================================================

CREATE TABLE title_genres (
    title_id INTEGER NOT NULL,

    genre_id SMALLINT NOT NULL,

    CONSTRAINT pk_title_genres
        PRIMARY KEY (title_id, genre_id),

    CONSTRAINT fk_title_genres_title
        FOREIGN KEY (title_id)
        REFERENCES titles(title_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_title_genres_genre
        FOREIGN KEY (genre_id)
        REFERENCES genres(genre_id)
        ON DELETE RESTRICT
);


-- ============================================================
-- 8. EPISODES TABLE
-- ============================================================

CREATE TABLE episodes (
    episode_id INTEGER PRIMARY KEY,

    title_id INTEGER NOT NULL,

    season_no SMALLINT NOT NULL
        CHECK (season_no > 0),

    episode_no SMALLINT NOT NULL
        CHECK (episode_no > 0),

    episode_title VARCHAR(200) NOT NULL,

    runtime_min SMALLINT NOT NULL
        CHECK (runtime_min > 0),

    release_date DATE NOT NULL,

    CONSTRAINT uq_episode_position
        UNIQUE (title_id, season_no, episode_no),

    -- Supports the composite foreign key in viewing_activity.
    CONSTRAINT uq_episode_title
        UNIQUE (episode_id, title_id),

    CONSTRAINT fk_episodes_title
        FOREIGN KEY (title_id)
        REFERENCES titles(title_id)
        ON DELETE RESTRICT
);


-- ============================================================
-- 9. VIEWING_ACTIVITY TABLE
-- ============================================================

CREATE TABLE viewing_activity (
    view_id INTEGER PRIMARY KEY,

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

    -- Ensures that an episode belongs to the same title
    -- specified in the viewing record.
    --
    -- If episode_id is NULL (movie play), PostgreSQL
    -- does not enforce this composite foreign key.

    CONSTRAINT fk_viewing_episode_title
        FOREIGN KEY (episode_id, title_id)
        REFERENCES episodes(episode_id, title_id)
        MATCH SIMPLE
        ON DELETE RESTRICT
);


-- ============================================================
-- 10. RATINGS TABLE
-- ============================================================

CREATE TABLE ratings (
    profile_id INTEGER NOT NULL,

    title_id INTEGER NOT NULL,

    rating VARCHAR(12) NOT NULL
        CHECK (
            rating IN ('THUMBS_DOWN', 'THUMBS_UP', 'LOVE')
        ),

    rated_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT pk_ratings
        PRIMARY KEY (profile_id, title_id),

    CONSTRAINT fk_ratings_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles(profile_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_ratings_title
        FOREIGN KEY (title_id)
        REFERENCES titles(title_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 11. MY_LIST TABLE
-- ============================================================

CREATE TABLE my_list (
    profile_id INTEGER NOT NULL,

    title_id INTEGER NOT NULL,

    added_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT pk_my_list
        PRIMARY KEY (profile_id, title_id),

    CONSTRAINT fk_my_list_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles(profile_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_my_list_title
        FOREIGN KEY (title_id)
        REFERENCES titles(title_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 12. INVOICES TABLE
-- ============================================================

CREATE TABLE invoices (
    invoice_id INTEGER PRIMARY KEY,

    account_id INTEGER NOT NULL,

    billing_period_start DATE NOT NULL,

    amount_inr NUMERIC(8,2) NOT NULL
        CHECK (amount_inr >= 0),

    status VARCHAR(10) NOT NULL
        CHECK (status IN ('PAID', 'FAILED', 'REFUNDED')),

    paid_at TIMESTAMPTZ,

    CONSTRAINT fk_invoices_account
        FOREIGN KEY (account_id)
        REFERENCES accounts(account_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_billing_period
        CHECK (
            EXTRACT(DAY FROM billing_period_start) = 1
        ),

    CONSTRAINT chk_invoice_payment
        CHECK (
            (status IN ('PAID', 'REFUNDED') AND paid_at IS NOT NULL)
            OR
            (status = 'FAILED' AND paid_at IS NULL)
        ),

    CONSTRAINT uq_account_billing_period
        UNIQUE (account_id, billing_period_start)
);


-- ============================================================
-- SCHEMA CREATION COMPLETED
-- ============================================================

SET search_path TO netflix;

-- Display all created tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'netflix'
ORDER BY table_name;


-- ============================================================
-- END OF FILE
-- ============================================================