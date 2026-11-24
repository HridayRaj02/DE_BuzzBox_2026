# Phase 4 – Optimization Report

## 1. Environment and method

| Item | Value |
|---|---|
| Project / team | Netflix Movie & Series Streaming Database / T0107 |
| Database engine | PostgreSQL 18 (`team.json`) |
| Database/schema | `netflix_bench` / `netflix` |
| Machine | MacBook Pro (`team.json`) |
| Dataset | Seed data: 200,401 viewing records; 133,057 invoices; 75,000 profiles; 25,000 accounts; 20,000 episodes; 59,992 My List rows; 33,900 ratings; 5,963 title-genre links; 3,000 titles; 15 genres; 4 plans |
| Method | Three runs per query with `EXPLAIN (ANALYZE, BUFFERS)`; average reported |
| Writes | The benchmark script wraps W01–W05 in `BEGIN` / `ROLLBACK` |

Baseline and optimized summaries and 30 raw plans for each run set are present under `benchmarks/results/baseline/` and `benchmarks/results/optimized/`. The comparisons below use the averages in those CSV files.

## 2. Baseline bottlenecks

The baseline averages sum to **6,563.538 ms**. R19 dominates at **6,109.484 ms**: its correlated count and latest-view subqueries repeatedly scan viewing activity for each Original. Other expensive reads are R16 (**119.762 ms**) and R23 (**42.755 ms**). R09 and R18 take about 25 ms each.

The baseline plans show sequential scans on `viewing_activity` for R01, R03, R08, R09, R13, R14, R16, R18, R19, and R23. R10 scans accounts for `lower(email)`, and R24 scans profiles for an account filter. Some scans are already fast on the seed dataset, including R22 (0.152 ms) and R25 (0.772 ms).

R13’s original `NOT IN` may return no rows when the subquery contains NULL episode IDs. The optimized query uses `NOT EXISTS`. This is a correctness fix with an intended result change; the returned rows still need an explicit comparison recorded in the deliverable.

## 3. Index design (`sql/05_indexes.sql`)

The index script creates 18 secondary indexes and enables `pg_trgm` for substring search. The actual optimized plans show use of the activity, title-search, account, invoice, profile, genre, and My List indexes. Broad analytics still scan substantial data.

| Index | Main query | Purpose |
|---|---|---|
| `viewing_activity_profile_unfinished_idx` (partial) | R01 | Finds unfinished views for a profile in title/latest order. |
| `viewing_activity_profile_started_idx` | R14 | Provides a profile-to-viewing access path for kids-profile checks. |
| `viewing_activity_title_started_idx` | R19 | Supports title-specific count and latest-view lookups. |
| `viewing_activity_episode_idx` (partial) | R13 | Supports anti-join probes and excludes NULL episode IDs. |
| `viewing_activity_started_idx` | R03, R08, R09, R18, R23 | Supports timestamp ranges and newest-first activity order. |
| `titles_maturity_added_idx` | R04 | Maturity filtering and recent-addition ordering. |
| `titles_leaving_idx` (partial) | R22 | Searches titles with a leaving date. |
| `titles_name_trgm_idx` (GIN, `pg_trgm`) | R05 | Supports `ILIKE '%love%'`. |
| `title_genres_genre_idx` | R04, R09, R25 | Adds a lookup path beginning with `genre_id`. |
| `accounts_lower_email_idx` (expression) | R10 | Matches `lower(email)`. |
| `accounts_status_next_billing_idx` | R21 | Matches status and due date. |
| `accounts_cancelled_idx` (partial) | R12 | Indexes dates for cancelled accounts. |
| `profiles_account_created_idx` | R24 | Finds an account’s profiles in creation order. |
| `profiles_kids_idx` (partial) | R14 | Finds kids profiles; observed in the optimized plan. |
| `invoices_status_period_idx` | R11, W05 | Supports status/period invoice lookup; observed for both queries. |
| `invoices_account_period_status_idx` | W05 | Account-correlated invoice lookup candidate; confirm if planner uses it. |
| `my_list_profile_added_idx` | R06 | Profile filter and most-recently-added ordering. |
| `my_list_added_title_idx` | R20 | Filters additions by date and groups by title. |

R17 aggregates all ratings, so a sequential scan remains reasonable. The W04 plan scans all active accounts and plans; a low-selectivity status index may not help a bulk billing run.

## 4. Query rewrites (`sql/06_optimized_queries.sql`)

Four queries are rewritten; the other 26 retain the original query logic.

| Query | Change | Reason |
|---|---|---|
| R09 | Year extraction → half-open timestamp range | Makes the timestamp predicate usable as an index condition. |
| R12 | Year extraction → half-open date range | Makes the cancelled-date filter sargable. |
| R13 | `NOT IN` → `NOT EXISTS` | Corrects NULL behavior; results intentionally differ from the faulty original. |
| R18 | Cast of `started_at` to date → timestamp lower bound | Avoids applying a function to the indexed timestamp column. |

The date-range rewrites use midnight in the session time zone to match the original expressions. The benchmark demonstrates their execution times, but row-count or `EXCEPT` comparisons for R09, R12, and R18 are not included in the available artifacts. Record those checks; for R13, document the original and corrected results separately.

## 5. Before-and-after results

Average execution time in milliseconds. Speed-up is baseline average divided by optimized average; values below 1× indicate a slower optimized run.

| Query | Type | Baseline | Optimized | Speed-up |
|---|---|---:|---:|---:|
| R01 | READ | 9.348 | 0.037 | 252.65× |
| R02 | READ | 0.068 | 0.035 | 1.94× |
| R03 | READ | 6.686 | 0.476 | 14.05× |
| R04 | READ | 0.559 | 0.368 | 1.52× |
| R05 | READ | 0.603 | 0.173 | 3.49× |
| R06 | READ | 0.052 | 0.044 | 1.18× |
| R07 | READ | 0.019 | 0.019 | 1.00× |
| R08 | READ | 7.485 | 1.659 | 4.51× |
| R09 | READ | 24.589 | 12.597 | 1.95× |
| R10 | READ | 2.886 | 0.028 | 103.07× |
| R11 | READ | 6.524 | 2.607 | 2.50× |
| R12 | READ | 1.236 | 0.500 | 2.47× |
| R13 | READ | 16.628 | 0.062 | 268.19×* |
| R14 | READ | 20.267 | 19.388 | 1.05× |
| R15 | READ | 3.883 | 4.082 | 0.95× |
| R16 | READ | 119.762 | 119.792 | 1.00× |
| R17 | READ | 5.138 | 4.861 | 1.06× |
| R18 | READ | 25.878 | 15.983 | 1.62× |
| R19 | READ | 6,109.484 | 3.890 | 1,570.56× |
| R20 | READ | 2.627 | 1.233 | 2.13× |
| R21 | READ | 1.086 | 0.272 | 3.99× |
| R22 | READ | 0.152 | 0.066 | 2.30× |
| R23 | READ | 42.755 | 12.926 | 3.31× |
| R24 | READ | 2.326 | 0.027 | 86.15× |
| R25 | READ | 0.772 | 0.446 | 1.73× |
| W01 | WRITE | 0.708 | 0.790 | 0.90× |
| W02 | WRITE | 0.558 | 0.601 | 0.93× |
| W03 | WRITE | 0.620 | 0.340 | 1.82× |
| W04 | WRITE | 136.336 | 157.011 | 0.87× |
| W05 | WRITE | 14.503 | 7.739 | 1.87× |
| **Total (30 averages)** | | **6,563.538** | **368.052** | **17.83×** |

*R13’s ratio compares execution time only; its rewritten query also fixes the original NULL-related result bug.

### Main observed gains and costs

- **R19:** 6,109.484 ms → 3.890 ms. The optimized plan uses an index-only scan on `viewing_activity_title_started_idx` instead of scanning viewing activity for each Original.
- **R01:** 9.348 ms → 0.037 ms. The plan uses an index-only scan on the partial unfinished-view index.
- **R10:** 2.886 ms → 0.028 ms. The functional index is used for the case-insensitive email lookup.
- **R13:** 16.628 ms → 0.062 ms. The episode index supports the corrected `NOT EXISTS` probe.
- **R16:** essentially unchanged (119.762 ms → 119.792 ms); its plan still scans and groups the full activity history.
- **R15** is slightly slower (3.883 ms → 4.082 ms); **W01**, **W02**, and **W04** also take longer after indexing. W04 rose from 136.336 ms to 157.011 ms. These are measured workload-level changes; per-index write cost and index size have not been isolated.

## 6. Correctness, storage, and reproducibility

| Check | Status |
|---|---|
| Baseline and optimized summaries | Present; each contains 30 query averages and scan-node summaries. |
| Raw plans | 30 baseline and 30 optimized files are present. |
| R09, R12, R18 result equivalence | Not shown in available artifacts; add row-count or `EXCEPT` checks. |
| R13 correction | SQL is rewritten; explicitly record original versus corrected output. |
| Index sizes | Not measured in this report. Use `pg_relation_size` for each created index. |
| Per-index write overhead | Not isolated; only before/after query averages are available. |

The optimized workload can be reproduced with:

```bash
./benchmarks/run_benchmark.sh netflix_bench optimized 3 sql/06_optimized_queries.sql
```

The current index and optimized-query files were reviewed against the Netflix schema and workload. Keep the original `queries/workload_30.sql` unchanged.
