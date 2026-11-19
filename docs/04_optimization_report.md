# Phase 4 – Optimization Report

## 1. Environment and measurement method

| Item | Value |
|---|---|
| Project | Netflix Movie & Series Streaming Database |
| Team | T0107 |
| Database engine | PostgreSQL 18 (from `team.json`) |
| Database/schema | `netflix_bench` / `netflix` (as used by the workload and benchmark command) |
| Machine | MacBook Pro (from `team.json`) |
| Dataset | Seed data: 25,000 accounts; 75,000 profiles; 3,000 titles; 20,000 episodes; 200,401 viewing records; 33,900 ratings; 59,992 My List rows; 133,057 invoices |
| Measurement | `EXPLAIN (ANALYZE, BUFFERS)`, 3 runs per query; average reported |
| Write safety | The benchmark script executes write queries inside `BEGIN` / `ROLLBACK` |

**Status:** The project has a baseline summary and raw plans. `benchmarks/results/optimized/summary.csv` is empty, so after timings, speed-ups, optimized-plan changes, correctness comparisons, index sizes, and write overhead are not yet measured. The figures in the attached example are from another run and are not copied here.

## 2. Baseline findings

The baseline average times sum to **6,563.538 ms** across all 30 queries. The most urgent bottleneck is R19 at **6,109.484 ms**: its correlated subqueries repeatedly access viewing activity by title. R16 takes **119.762 ms** for a broad grouping by account and hour; R23 takes **42.755 ms** for a deep page using `OFFSET 150000`. R09 and R18 take **24.589 ms** and **25.878 ms** for date-based analytics.

The baseline plan summary shows sequential scans on `viewing_activity` for R01, R03, R08, R09, R13, R14, R16, R18, R19, and R23. R10 scans accounts for `lower(email)`, while R24 scans profiles to find one account’s profiles. Some small-table scans are already fast: R22 takes 0.152 ms and R25 takes 0.772 ms.

R13’s original `NOT IN` query is vulnerable to NULLs from viewing records without an episode ID. The optimized query uses `NOT EXISTS` to find unwatched episodes. This is a correctness fix that intentionally changes the original result; compare and report the actual rows returned after running it.

## 3. Index design (`sql/05_indexes.sql`)

The index script defines 18 secondary indexes and enables `pg_trgm` for R05. These are candidates based on the baseline predicates and plans. Confirm their use, storage, and effect on writes with the optimized run.

| Index | Query | Reason |
|---|---|---|
| `viewing_activity_profile_unfinished_idx` (partial) | R01 | Profile and title ordering for unfinished views; includes only `NOT completed` rows. |
| `viewing_activity_profile_started_idx` | R14 | Potential profile-to-viewing probes when starting from kids profiles; verify in the plan. |
| `viewing_activity_title_started_idx` | R19 | Supports title-specific counts and latest-view lookups. |
| `viewing_activity_episode_idx` (partial) | R13 | Supports the anti-join by episode ID and excludes NULL episode IDs. |
| `viewing_activity_started_idx` | R03, R08, R09, R18, R23 | Timestamp ranges and newest-first activity order; broad analytics may still favor a sequential scan. |
| `titles_maturity_added_idx` | R04 | Maturity filter and recent-addition ordering. |
| `titles_leaving_idx` (partial) | R22 | Finds titles with a scheduled leaving date. |
| `titles_name_trgm_idx` (GIN, `pg_trgm`) | R05 | Supports `ILIKE '%love%'`, which a normal B-tree cannot efficiently serve. |
| `title_genres_genre_idx` | R04, R09, R25 | Reverse lookup by genre; the primary key begins with `title_id`. |
| `accounts_lower_email_idx` (expression) | R10 | Matches the query’s `lower(email)` expression. |
| `accounts_status_next_billing_idx` | R21 and selective status filters | Matches status and billing-date filters; broad account queries may still scan. |
| `accounts_cancelled_idx` (partial) | R12 | Cancellation dates for cancelled accounts; used with the rewritten date range. |
| `profiles_account_created_idx` | R24 | Finds one account’s profiles in creation order. |
| `profiles_kids_idx` (partial) | R14 | Potentially enumerates kids profiles before activity probes; verify the chosen plan. |
| `invoices_status_period_idx` | R11 | Failed-invoice lookup by status and billing period. |
| `invoices_account_period_status_idx` | W05 | Matches the account-correlated invoice existence check. |
| `my_list_profile_added_idx` | R06 | Finds one profile’s list in most-recently-added order. |
| `my_list_added_title_idx` | R20 | Filters additions by date and groups them by title. |

R17 aggregates all ratings, and a sequential scan may remain the efficient plan; no extra ratings index is created. The index script does not alter the schema or seed data.

## 4. Query rewrites (`sql/06_optimized_queries.sql`)

Four queries are rewritten; the remaining 26 retain their original query logic. R09, R12, and R18 use sargable date ranges. R13 fixes a NULL-related correctness bug.

| Query | Rewrite | Reason |
|---|---|---|
| R09 | `EXTRACT(YEAR FROM started_at) = 2026` → half-open timestamp range for 2026 | Applying `EXTRACT` to the column blocks a normal timestamp index condition. Bounds use the session time zone, like the original year extraction. |
| R12 | `EXTRACT(YEAR FROM cancelled_on) = 2026` → `cancelled_on >= DATE '2026-01-01' AND cancelled_on < DATE '2027-01-01'` | Lets the cancellation-date index support a range condition. |
| R13 | `NOT IN (subquery)` → correlated `NOT EXISTS` | Avoids NULL propagation from movie views with no episode ID; intended result differs from the faulty original. |
| R18 | `started_at::date >= '2026-01-01'` → timestamp lower bound | Avoids casting the indexed column; both forms use midnight in the session time zone. |

Row-count or `EXCEPT` checks for R09, R12, and R18 are pending. For R13, record both the original and corrected results and explain the intended result rather than claiming equivalence.

## 5. Baseline and optimized timings

Times are milliseconds. Baseline values are averages from `benchmarks/results/baseline/summary.csv`. Optimized values and speed-ups remain pending because the optimized summary is empty.

| Query | Type | Baseline avg | Optimized avg | Speed-up |
|---|---|---:|---:|---:|
| R01: Continue Watching | READ | 9.348 | — | Pending |
| R02: Episodes per season | READ | 0.068 | — | Pending |
| R03: Top titles on 30 June | READ | 6.686 | — | Pending |
| R04: Kids Comedy row | READ | 0.559 | — | Pending |
| R05: Search title names | READ | 0.603 | — | Pending |
| R06: My List | READ | 0.052 | — | Pending |
| R07: Next episode | READ | 0.019 | — | Pending |
| R08: Binge sessions | READ | 7.485 | — | Pending |
| R09: Completion rate per genre | READ | 24.589 | — | Pending |
| R10: Case-insensitive sign-in | READ | 2.886 | — | Pending |
| R11: Failed June invoices | READ | 6.524 | — | Pending |
| R12: Cancellations and tenure | READ | 1.236 | — | Pending |
| R13: Unwatched episodes | READ | 16.628 | — | Pending |
| R14: Kids maturity violations | READ | 20.267 | — | Pending |
| R15: Revenue by plan | READ | 3.883 | — | Pending |
| R16: Account sharing by hour | READ | 119.762 | — | Pending |
| R17: Ratings by Original status | READ | 5.138 | — | Pending |
| R18: Viewing hours by device/month | READ | 25.878 | — | Pending |
| R19: Original-title view totals | READ | 6,109.484 | — | Pending |
| R20: Most-added titles | READ | 2.627 | — | Pending |
| R21: On-hold accounts past due | READ | 1.086 | — | Pending |
| R22: Titles leaving in July | READ | 0.152 | — | Pending |
| R23: Activity page 6,001 | READ | 42.755 | — | Pending |
| R24: Profiles for account 1409 | READ | 2.326 | — | Pending |
| R25: Similar titles by genre | READ | 0.772 | — | Pending |
| W01: Insert viewing event | WRITE | 0.708 | — | Pending |
| W02: Add to My List | WRITE | 0.558 | — | Pending |
| W03: Change plan | WRITE | 0.620 | — | Pending |
| W04: Monthly invoice batch | WRITE | 136.336 | — | Pending |
| W05: Dunning update | WRITE | 14.503 | — | Pending |
| **Total (30 query averages)** | | **6,563.538** | — | Pending |

## 6. Expected gains and costs to measure

R19 is the highest-priority query to remeasure after adding `viewing_activity_title_started_idx`. R01, R03, R10, R13, R23, and R24 also have matching index or query changes. R16 aggregates the full viewing history and is likely to remain scan-bound. R09 and R18 aggregate broad date ranges, so a sequential scan may still be cheaper than an index scan.

Every added index has a storage and write-maintenance cost. Measure W01–W05 after indexing, especially W04’s invoice batch. Record each index’s size with `pg_relation_size` and compare the before/after plans. No read/write trade-off is claimed without those measurements.

## 7. Reproducibility and verification status

| Check | Status |
|---|---|
| Baseline | Available: 30 averages and scan-node summaries in `benchmarks/results/baseline/summary.csv` |
| Optimized summary and raw plans | Pending: `benchmarks/results/optimized/summary.csv` is empty |
| Index script applied to the database | Not verified from this environment |
| R09, R12, R18 result equivalence | Pending row-count or `EXCEPT` comparisons |
| R13 corrected result | Pending database comparison; document its difference from the original query |
| Write overhead and index sizes | Pending optimized benchmark and `pg_relation_size` measurements |

After loading the seed data and applying `sql/05_indexes.sql` to the project database, run:

```bash
./benchmarks/run_benchmark.sh netflix_bench optimized 3 sql/06_optimized_queries.sql
```

Use the same machine, database contents, and run count as the baseline, then replace the pending cells with measured results.
