# Phase 2 – Schema Design

**Project:** Netflix Movie & Series Streaming Database\
**Course:** Database Management Systems · **Year:** B.Tech 2nd year ·
**Team size:** 4\
**Database:** PostgreSQL 15 or newer

---

## How we figured out the schema

We looked at the CSV files in `seed_data.zip`, checked their column names and sample rows, and used the project queries to see how the tables connect. Then we chose a type and key for each column.

Everything is in the `netflix` schema: `CREATE SCHEMA netflix; SET search_path TO netflix;`

---

## Data Dictionary

### Table: `plans`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| plan_id | SMALLINT | PK | There are only four plans |
| plan_name | VARCHAR(20) | NOT NULL, UNIQUE | Each plan has a different name |
| monthly_price_inr | NUMERIC(8,2) | NOT NULL, >= 0 | Price needs decimal places |
| max_streams | SMALLINT | NOT NULL, > 0 | Number of screens that can stream |
| max_resolution | VARCHAR(10) | NOT NULL | For example 480p, 1080p, or 4K |
| has_ads | BOOLEAN | NOT NULL | True or false from the CSV |

Indexes that exist automatically: PK on `plan_id`, UNIQUE on `plan_name`.

---

### Table: `accounts`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| account_id | INTEGER | PK | Unique account number |
| email | VARCHAR(254) | NOT NULL, UNIQUE | Used to sign in |
| phone | VARCHAR(15) | NULL, UNIQUE | Some accounts do not have a phone number |
| country_code | CHAR(2) | NOT NULL | Short country code, such as IN |
| plan_id | SMALLINT | NOT NULL, FK → plans | Every account has a plan |
| signup_date | DATE | NOT NULL | Date the account was created |
| status | VARCHAR(10) | NOT NULL | ACTIVE, ON_HOLD, or CANCELLED |
| cancelled_on | DATE | NULL | Empty if account is not cancelled |
| next_billing_date | DATE | NULL | Empty for cancelled accounts |

**Data note:** The sign-in query checks `LOWER(email)`. A plain index on email will not speed that exact search. A unique index on `LOWER(email)` can support case-insensitive sign-in and prevent duplicate emails with different capitalization.

---

### Table: `profiles`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| profile_id | INTEGER | PK | Unique profile number |
| account_id | INTEGER | NOT NULL, FK → accounts | Every profile belongs to an account |
| profile_name | VARCHAR(50) | NOT NULL | Name shown when choosing a profile |
| is_kids | BOOLEAN | NOT NULL | Shows whether this is a kids profile |
| maturity_limit | VARCHAR(5) | NOT NULL | U, UA7, UA13, UA16, or A |
| language | VARCHAR(30) | NOT NULL | Profile language |
| created_at | TIMESTAMPTZ | NOT NULL | Date and time, including timezone |

---

### Table: `genres`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| genre_id | SMALLINT | PK | There are only 15 genres |
| genre_name | VARCHAR(40) | NOT NULL, UNIQUE | Each genre has a different name |

---

### Table: `titles`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| title_id | INTEGER | PK | Unique movie or series number |
| title_type | VARCHAR(10) | NOT NULL | MOVIE or SERIES |
| name | VARCHAR(200) | NOT NULL | Title name |
| release_year | SMALLINT | NOT NULL | The year it was released |
| maturity_rating | VARCHAR(5) | NOT NULL | U, UA7, UA13, UA16, or A |
| original_language | VARCHAR(30) | NOT NULL | Language of the title |
| runtime_min | SMALLINT | NULL, > 0 when present | Runtime in minutes; can be empty for a series |
| is_netflix_original | BOOLEAN | NOT NULL | Whether Netflix made the title |
| added_on | DATE | NOT NULL | Date added to Netflix |
| leaving_on | DATE | NULL | Empty if it is not scheduled to leave |

---

### Table: `title_genres`
**Composite PK: `(title_id, genre_id)`** — a title can have multiple genres, and each genre can be used by many titles.

| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| title_id | INTEGER | PK (part 1), FK → titles | Title in this genre link |
| genre_id | SMALLINT | PK (part 2), FK → genres | Genre in this title link |

---

### Table: `episodes`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| episode_id | INTEGER | PK | Unique episode number |
| title_id | INTEGER | NOT NULL, FK → titles | Series this episode belongs to |
| season_no | SMALLINT | NOT NULL, > 0 | Season number |
| episode_no | SMALLINT | NOT NULL, > 0 | Episode number within the season |
| episode_title | VARCHAR(200) | NOT NULL | Name of the episode |
| runtime_min | SMALLINT | NOT NULL, > 0 | Episode length in minutes |
| release_date | DATE | NOT NULL | Episode release date |

Add UNIQUE on `(title_id, season_no, episode_no)` so the same episode position is not used twice in a series.

---

### Table: `viewing_activity`
This is the main activity table. The project data has 200,401 viewing records.

| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| view_id | INTEGER | PK | Unique viewing record |
| profile_id | INTEGER | NOT NULL, FK → profiles | Profile that watched |
| title_id | INTEGER | NOT NULL, FK → titles | Movie or series watched |
| episode_id | INTEGER | NULL, FK → episodes | Empty for movie plays |
| started_at | TIMESTAMPTZ | NOT NULL | Viewing date and time with timezone |
| duration_watched_sec | INTEGER | NOT NULL, >= 0 | Number of seconds watched |
| device_type | VARCHAR(10) | NOT NULL | Device used, such as TV or MOBILE |
| completed | BOOLEAN | NOT NULL | Whether viewing was marked complete |

`episode_id` can be empty because some viewing records are for movies. When it is filled in, the episode should belong to the same title in that row.

---

### Table: `ratings`
**Composite PK: `(profile_id, title_id)`** — each profile has at most one rating for a title.

| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| profile_id | INTEGER | PK (part 1), FK → profiles | Profile that rated |
| title_id | INTEGER | PK (part 2), FK → titles | Title that was rated |
| rating | VARCHAR(12) | NOT NULL | THUMBS_DOWN, THUMBS_UP, or LOVE |
| rated_at | TIMESTAMPTZ | NOT NULL | When the rating was given |

---

### Table: `my_list`
**Composite PK: `(profile_id, title_id)`** — a profile cannot add the same title twice.

| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| profile_id | INTEGER | PK (part 1), FK → profiles | Profile that saved the title |
| title_id | INTEGER | PK (part 2), FK → titles | Saved title |
| added_at | TIMESTAMPTZ | NOT NULL | When it was added |

---

### Table: `invoices`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| invoice_id | INTEGER | PK | Unique invoice number |
| account_id | INTEGER | NOT NULL, FK → accounts | Account being billed |
| billing_period_start | DATE | NOT NULL | First day of the billing month |
| amount_inr | NUMERIC(8,2) | NOT NULL, >= 0 | Amount charged in rupees |
| status | VARCHAR(10) | NOT NULL | PAID or FAILED |
| paid_at | TIMESTAMPTZ | NULL | Empty when the invoice was not paid |

---

## ER Diagram

See `diagrams/er_diagram.png` for the diagram.

**Relationships:**
- `plans` → `accounts`: 1:N (one plan can be used by many accounts)
- `accounts` → `profiles`: 1:N (one account can have multiple profiles)
- `accounts` → `invoices`: 1:N (one account has invoices over time)
- `profiles` → `viewing_activity`: 1:N (one profile can have many viewing records)
- `titles` → `viewing_activity`: 1:N (one title can be watched many times)
- `titles` → `episodes`: 1:N (a series has episodes)
- `episodes` → `viewing_activity`: 1:N (an episode can be watched many times)
- `titles` ↔ `genres`: M:N using `title_genres`
- `profiles` ↔ `titles`: M:N using `ratings`
- `profiles` ↔ `titles`: M:N using `my_list`

---

## Normal Form Analysis

**plans:** `plan_id` identifies each plan. Plan name, price and stream limit depend on that plan. **3NF**

**accounts:** `account_id` identifies an account. Its email, plan and dates describe that account. Plan details are stored separately in `plans`. **3NF**

**profiles:** `profile_id` identifies a profile. Profile details depend on that ID, and account details stay in `accounts`. **3NF**

**genres:** `genre_id` identifies the genre name. **3NF**

**titles:** `title_id` identifies title information. Genre links are stored separately in `title_genres`, so genre names are not repeated in this table. **3NF**

**title_genres:** The two columns together identify one title and genre link. **3NF**

**episodes:** `episode_id` identifies the episode. The title, season and episode number describe where it belongs. **3NF**

**viewing_activity:** `view_id` identifies one viewing event. Profile, title, device and time describe that event. **3NF**

**ratings:** `(profile_id, title_id)` identifies one rating. The rating and date depend on both parts of the key. **3NF**

**my_list:** `(profile_id, title_id)` identifies one saved title for a profile. **3NF**

**invoices:** `invoice_id` identifies an invoice. `amount_inr` is kept here because it records the billed amount at the time, even if the plan price changes later. **3NF**

---

## Integrity Checks to Run After Loading

These checks should be run after loading the CSV files into PostgreSQL:

| Check | What to check |
|-------|---------------|
| IC1 | Every account has a plan that exists in `plans` |
| IC2 | Every profile belongs to an account that exists |
| IC3 | Every viewing record has a real profile and title |
| IC4 | Every episode in a viewing record belongs to its title |
| IC5 | Ratings and My List rows point to real profiles and titles |
| IC6 | Every invoice belongs to a real account |
| IC7 | No duplicate primary or composite keys |

Expected row counts from the project data:

| Table | Expected rows |
|-------|--------------:|
| plans | 4 |
| accounts | 25,000 |
| profiles | 75,000 |
| genres | 15 |
| titles | 3,000 |
| title_genres | 5,963 |
| episodes | 20,000 |
| viewing_activity | 200,401 |
| ratings | 33,900 |
| my_list | 59,992 |
| invoices | 133,057 |

## Data Problems and Notes

1. **Email search ignores letter case:** R10 searches with `LOWER(email)`. An index on `LOWER(email)` can help this query.
2. **Some account phone numbers are empty:** `phone` must allow NULL values.
3. **Some dates are empty:** `cancelled_on`, `next_billing_date`, `leaving_on`, and `paid_at` can be NULL depending on account or title status.
4. **Movies do not have an episode:** `episode_id` is NULL for movie viewing records.
5. **The R13 query has a NULL issue:** it uses `NOT IN` with episode IDs from viewing activity. Since some episode IDs are NULL, this query may return no episodes. `NOT EXISTS` avoids this issue.

