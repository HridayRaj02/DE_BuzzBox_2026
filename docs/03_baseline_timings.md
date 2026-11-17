# Phase 3 – Baseline Query Timings

**Project:** Netflix Movie & Series Streaming Database | **Team:** T0107 | **Database:** PostgreSQL 18 | **Machine:** MacBook Pro  
**Method:** `EXPLAIN (ANALYZE, BUFFERS)` · 3 runs per query · report the mean · execute write queries inside `BEGIN … ROLLBACK`  
**Data:** 25,000 accounts · 75,000 profiles · 3,000 titles · 20,000 episodes · 200,401 viewing records · 33,900 ratings · 59,992 My List rows · 133,057 invoices  
**Indexes present:** Primary key and UNIQUE constraint indexes only; no manually created tuning indexes.

Raw plans: `benchmarks/results/baseline/R01.txt` … `W05.txt`  
Summary CSV: `benchmarks/results/baseline/summary.csv`

> **Measurement status:** No baseline result file was present when this report was prepared. The timing cells below are intentionally blank. Run `benchmarks/run_benchmark.sh` against the loaded `netflix` schema and fill them from its summary output; do not treat estimates as measured timings.

---

# Phase 3: Baseline Query Timings

## 1. Benchmark Methodology

The baseline benchmark was executed against the `netflix_db` database using the provided `benchmarks/run_benchmark.sh` script.

- Total queries benchmarked: 30
- Read queries: 25 (R01–R25)
- Write queries: 5 (W01–W05)
- Runs per query: 3
- Measurement: PostgreSQL `EXPLAIN (ANALYZE, BUFFERS)` execution time
- Write queries were executed inside transactions and rolled back to prevent permanent data changes.

The benchmark output is stored in `benchmarks/results/baseline/`.

## 2. Baseline Timing Results

All execution times are in milliseconds (ms).

| Query | Type | Run 1 | Run 2 | Run 3 | Average |
|---|---|---:|---:|---:|---:|
| R01 | READ | 14.240 | 7.442 | 6.363 | 9.348 |
| R02 | READ | 0.066 | 0.098 | 0.039 | 0.068 |
| R03 | READ | 5.279 | 7.549 | 7.230 | 6.686 |
| R04 | READ | 0.596 | 0.554 | 0.528 | 0.559 |
| R05 | READ | 0.613 | 0.590 | 0.605 | 0.603 |
| R06 | READ | 0.053 | 0.051 | 0.052 | 0.052 |
| R07 | READ | 0.020 | 0.018 | 0.019 | 0.019 |
| R08 | READ | 7.368 | 7.571 | 7.516 | 7.485 |
| R09 | READ | 24.592 | 23.763 | 25.411 | 24.589 |
| R10 | READ | 3.048 | 2.796 | 2.813 | 2.886 |
| R11 | READ | 6.884 | 6.352 | 6.335 | 6.524 |
| R12 | READ | 1.209 | 1.289 | 1.209 | 1.236 |
| R13 | READ | 16.358 | 16.747 | 16.778 | 16.628 |
| R14 | READ | 21.147 | 19.782 | 19.873 | 20.267 |
| R15 | READ | 3.854 | 3.917 | 3.878 | 3.883 |
| R16 | READ | 119.167 | 120.308 | 119.812 | 119.762 |
| R17 | READ | 5.479 | 4.959 | 4.976 | 5.138 |
| R18 | READ | 25.913 | 25.824 | 25.898 | 25.878 |
| R19 | READ | 6014.113 | 6138.327 | 6176.013 | 6109.484 |
| R20 | READ | 2.815 | 2.546 | 2.520 | 2.627 |
| R21 | READ | 1.108 | 1.095 | 1.055 | 1.086 |
| R22 | READ | 0.154 | 0.151 | 0.152 | 0.152 |
| R23 | READ | 38.533 | 40.317 | 49.416 | 42.755 |
| R24 | READ | 2.587 | 2.516 | 1.875 | 2.326 |
| R25 | READ | 0.966 | 0.665 | 0.684 | 0.772 |
| W01 | WRITE | 1.162 | 0.555 | 0.406 | 0.708 |
| W02 | WRITE | 0.655 | 0.574 | 0.444 | 0.558 |
| W03 | WRITE | 1.349 | 0.265 | 0.246 | 0.620 |
| W04 | WRITE | 129.128 | 144.973 | 134.907 | 136.336 |
| W05 | WRITE | 15.831 | 13.095 | 14.584 | 14.503 |

## 3. Query Execution Plan Analysis

### Read Queries

| Query | Observed Scan Type | Performance Explanation |
|---|---|---|
| R01 | Sequential Scan on viewing_activity; Index Scan on titles | Filtering viewing activity by profile and completion status requires scanning the activity table. |
| R02 | Index Scan on episodes | The composite index efficiently locates episodes for the requested series. |
| R03 | Sequential Scan on viewing_activity; Index Scan on titles | The date-based viewing filter scans activity records before grouping viewers by title. |
| R04 | Sequential Scan on title_genres; Index Scans on genres and titles | The genre mapping is scanned, while indexed lookups retrieve matching genres and titles. |
| R05 | Sequential Scan on titles | The leading wildcard in `ILIKE '%love%'` prevents an ordinary B-tree index from efficiently supporting the search. |
| R06 | Index Scans on my_list and titles | Primary-key and composite-key lookups make this profile-specific query efficient. |
| R07 | Index Scan on episodes | The composite episode index efficiently finds the next episode. |
| R08 | Sequential Scan on viewing_activity | The query processes viewing records and groups them by profile, title, and date. |
| R09 | Sequential Scans on viewing_activity, title_genres, and genres | Multiple joins and grouping across viewing records make this aggregation expensive. |
| R10 | Sequential Scan on accounts | Applying `LOWER(email)` requires evaluating the expression for account records without a matching functional index. |
| R11 | Sequential Scans on accounts and invoices | The query joins two tables and filters invoices by status and billing period. |
| R12 | Sequential Scan on accounts | Cancellation filtering and monthly aggregation require examining account records. |
| R13 | Index Scan on episodes; Sequential Scan on viewing_activity | The episode lookup is indexed, but the `NOT IN` subquery scans viewing activity to identify unwatched episodes. |
| R14 | Sequential Scans on viewing_activity, profiles, and titles | Multiple joins and maturity-rating comparisons require processing a large number of viewing records. |
| R15 | Sequential Scans on accounts and plans | Active accounts are joined with plans and aggregated to calculate monthly revenue. |
| R16 | Sequential Scans on viewing_activity, profiles, accounts, and plans | Multiple joins and grouping by account and hour across viewing activity create substantial processing overhead. |
| R17 | Sequential Scans on ratings and titles | All ratings are joined with titles and grouped by original-content status. |
| R18 | Sequential Scan on viewing_activity | Date filtering, device grouping, and duration aggregation require processing viewing records. |
| R19 | Sequential Scans on titles and viewing_activity | Correlated subqueries calculate total views and latest viewing time for each original title, repeatedly scanning viewing activity. |
| R20 | Sequential Scans on my_list and titles | The query filters list additions by date, joins titles, and aggregates the results. |
| R21 | Sequential Scan on accounts | Accounts are filtered by status and billing date, then sorted. |
| R22 | Sequential Scan on titles | The leaving-date filter is evaluated across titles without an index supporting the condition. |
| R23 | Sequential Scan on viewing_activity | Retrieving a deep page using `OFFSET 150000` requires processing and skipping a large number of rows. |
| R24 | Sequential Scan on profiles | Profiles are filtered by account ID and sorted by creation date. |
| R25 | Sequential Scan on title_genres; Index Only Scan on title_genres | The self-join uses the primary-key index for one side, while the other side scans the genre mapping records. |

### Write Queries

| Query | Observed Scan Type | Performance Explanation |
|---|---|---|
| W01 | Index Scan on episodes | The insert uses an indexed lookup to find the episode before inserting the viewing record. |
| W02 | No scan | The insert uses explicitly supplied values with conflict handling, so no source-table scan is needed. |
| W03 | Index Scans on plans and accounts | Indexed lookups find the STANDARD plan and the target account for the update. |
| W04 | Sequential Scans on accounts and plans | The bulk invoice insert processes all active accounts and joins their plans. |
| W05 | Sequential Scans on accounts and invoices | The update checks active accounts against failed invoices using an `EXISTS` condition. |

## 4. Key Baseline Observations

- R19 is the slowest query, with an average execution time of **6109.484 ms**. Its correlated subqueries repeatedly access the viewing activity table.
- W04 is the slowest write query, averaging **136.336 ms**, because it generates invoices for all active accounts.
- R16 takes **119.762 ms** due to multiple joins and grouping over viewing activity.
- R23 takes **42.755 ms**, with deep pagination requiring a large offset.
- R02, R06, and R07 are among the fastest queries because they use existing indexes effectively.
- Several queries use sequential scans, indicating opportunities for indexing and query optimization in the next phase.

## 5. Benchmark Artifacts

The benchmark generated the following files:

- `benchmarks/results/baseline/summary.csv` — average, median, minimum, maximum execution times and observed scan nodes.
- `benchmarks/results/baseline/R01.txt` through `R25.txt` — raw execution plans for all three runs of each read query.
- `benchmarks/results/baseline/W01.txt` through `W05.txt` — raw execution plans for all three runs of each write query.

These results will serve as the baseline for comparing query performance after optimization in Phase 4.
