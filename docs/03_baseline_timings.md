# Phase 3 – Baseline Query Timings

**Project:** Netflix Movie & Series Streaming Database | **Team:** T0107 | **Database:** PostgreSQL 18 | **Machine:** MacBook Pro  
**Method:** `EXPLAIN (ANALYZE, BUFFERS)` · 3 runs per query · report the mean · execute write queries inside `BEGIN … ROLLBACK`  
**Data:** 25,000 accounts · 75,000 profiles · 3,000 titles · 20,000 episodes · 200,401 viewing records · 33,900 ratings · 59,992 My List rows · 133,057 invoices  
**Indexes present:** Primary key and UNIQUE constraint indexes only; no manually created tuning indexes.

Raw plans: `benchmarks/results/baseline/R01.txt` … `W05.txt`  
Summary CSV: `benchmarks/results/baseline/summary.csv`

> **Measurement status:** No baseline result file was present when this report was prepared. The timing cells below are intentionally blank. Run `benchmarks/run_benchmark.sh` against the loaded `netflix` schema and fill them from its summary output; do not treat estimates as measured timings.

---

## Timing Table (all 30 queries)

| Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|-------|------|----------:|----------:|----------:|------------:|
| R01: Continue Watching for profile 7043 | READ | — | — | — | — |
| R02: Episode count by season for series 2909 | READ | — | — | — | — |
| R03: Most-watched titles on 30 June 2026 | READ | — | — | — | — |
| R04: Kids Comedy row, U/UA7 titles | READ | — | — | — | — |
| R05: Search titles containing “love” | READ | — | — | — | — |
| R06: My List for profile 7393 | READ | — | — | — | — |
| R07: Autoplay next episode of series 2909 | READ | — | — | — | — |
| R08: Binge sessions in June 2026 | READ | — | — | — | — |
| R09: Completion rate per genre in 2026 | READ | — | — | — | — |
| R10: Case-insensitive account sign-in | READ | — | — | — | — |
| R11: Failed June invoices for active/on-hold accounts | READ | — | — | — | — |
| R12: Monthly cancellations and average tenure | READ | — | — | — | — |
| R13: Unwatched episodes of series 2523 | READ | — | — | — | — |
| R14: Kids profiles watching above maturity limit | READ | — | — | — | — |
| R15: Monthly recurring revenue by plan | READ | — | — | — | — |
| R16: Accounts exceeding simultaneous stream limits | READ | — | — | — | — |
| R17: LOVE rating share, Originals vs licensed | READ | — | — | — | — |
| R18: Viewing hours per device per month | READ | — | — | — | — |
| R19: Views and latest view for every Original | READ | — | — | — | — |
| R20: Titles most added to My Lists in June | READ | — | — | — | — |
| R21: On-hold accounts past their billing date | READ | — | — | — | — |
| R22: Licensed titles leaving in July 2026 | READ | — | — | — | — |
| R23: Viewing activity, page 6,001 | READ | — | — | — | — |
| R24: Profiles belonging to account 1409 | READ | — | — | — | — |
| R25: Titles sharing at least two genres with series 2909 | READ | — | — | — | — |
| W01: Insert a viewing event for episode S1E5 | WRITE | — | — | — | — |
| W02: Add a title to My List | WRITE | — | — | — | — |
| W03: Change account 1409 to STANDARD plan | WRITE | — | — | — | — |
| W04: Create July invoices for active accounts | WRITE | — | — | — | — |
| W05: Put accounts on hold after failed June invoice | WRITE | — | — | — | — |
| **Total (sum of all 30)** | | | | | — |

---

## Expected Scan Patterns and Likely Cost Drivers

The notes below are hypotheses from the schema and SQL workload, not measured `EXPLAIN` output. PostgreSQL can choose sequential scans for small tables even when an index exists. Confirm each plan after collecting the baseline.

| Query | Likely scan / reason |
|-------|----------------------|
| R01 | `viewing_activity` likely sequential scan; no index begins with `(profile_id, title_id, started_at)` to find the profile’s latest unfinished plays. |
| R02 | `episodes` can use the UNIQUE index on `(title_id, season_no, episode_no)` if defined; filtering and grouping one series should be relatively selective. |
| R03 | `viewing_activity` likely sequential scan for the one-day range; no index on `started_at`. Then aggregate viewers and join titles. |
| R04 | `genres` UNIQUE index finds Comedy; `title_genres` PK begins with `title_id`, so reverse genre lookup may scan it. Titles are filtered by maturity and sorted by `added_on`. |
| R05 | Sequential scan on `titles`; `ILIKE '%love%'` has a leading wildcard and cannot use a normal B-tree index. |
| R06 | `my_list` composite PK starts with `profile_id`, supporting the profile lookup; title lookups use the titles PK. Sorting that profile’s saved rows may require a sort. |
| R07 | The episodes UNIQUE index supports the series prefix, but tuple comparison and order may still read several episodes before returning one row. |
| R08 | Sequential scan on `viewing_activity`; timestamp predicate and grouping by profile, title, and date have no matching composite index. |
| R09 | Sequential scan on viewing activity (year extraction), then joins through title_genres and genres and aggregates. |
| R10 | Sequential scan on accounts: `lower(email)` does not match the ordinary UNIQUE index on `email`. |
| R11 | Invoice filters on status and billing period lack a supporting index; account PK/FK joins are available, but the invoice scan is likely dominant. |
| R12 | Sequential scan on accounts; extracting year from `cancelled_on` prevents a simple date-range index condition. Aggregation groups cancellations by month. |
| R13 | `episodes` can use the `(title_id, season_no, episode_no)` index for the series filter. The `NOT IN` subquery scans viewing activity and includes NULL episode IDs; this can make the predicate return no rows. |
| R14 | Sequential scan on viewing activity with joins through profile and title PKs; maturity comparison is calculated row by row. |
| R15 | Sequential scan on accounts, then plan PK lookups and aggregation; accounts has no index on status. |
| R16 | Sequential scan of viewing activity and several joins, followed by a large grouping by account and hour. |
| R17 | Ratings scan and title PK lookups, then grouped aggregation; no additional index is necessary for the full-table report. |
| R18 | Sequential scan on viewing activity; `started_at::date` is applied to rows and there is no timestamp index. Grouping by month and device also needs aggregation. |
| R19 | Likely expensive correlated work: for each Original, two subqueries count and find max time in viewing activity by `title_id`; no index supports either lookup. |
| R20 | Sequential scan on My List for the June range; no index on `added_at`, then grouping and sorting by add count. |
| R21 | Sequential scan on accounts because status and next billing date have no supporting index. |
| R22 | Sequential scan on titles for `leaving_on`; no index on the date. |
| R23 | The timestamp ordering can use the viewing_activity PK only if the plan can satisfy the requested order (the PK is `view_id`, not `started_at`). Likely full scan plus sort, then discard 150,000 rows for OFFSET. |
| R24 | Sequential scan on profiles because the account FK has no index; then sort that account’s profiles by creation time. |
| R25 | `title_genres` PK supports the source-title lookup by `title_id`; joining other rows by `genre_id` lacks a leading index, so the self-join may scan the link table. |
| W01 | Insert into viewing_activity plus FK checks on profile/title/episode; referenced PK indexes support those checks. |
| W02 | Insert into My List; composite PK detects an existing `(profile_id, title_id)` pair. |
| W03 | Plan name lookup uses the plans UNIQUE index; account 1409 uses the accounts PK. |
| W04 | Bulk insert for active accounts; account scan and plan PK joins precede invoice inserts and FK/constraint checks. |
| W05 | Account update scans active accounts and checks invoice existence per candidate; invoice filters lack a supporting composite index. |

---

## Key Observations to Confirm After Running

1. **R19 is a likely top read-query cost.** The correlated count and maximum timestamp are repeated for each Netflix Original without an index on `viewing_activity.title_id`.
2. **R23 is sensitive to deep OFFSET pagination.** It must skip 150,000 rows, and no index orders viewing records by `started_at`.
3. **R16 and R09 are broad analytics queries.** They read and aggregate much of viewing activity; workload growth will increase their cost.
4. **R05 and R10 expose different index limitations.** A normal B-tree cannot help the leading-wildcard search; case-insensitive sign-in needs an expression index matching `lower(email)` if allowed in the optimization phase.
5. **R13 has a correctness issue as well as a performance concern.** `NOT IN` sees NULL episode IDs from movie views and can suppress all results. Record its baseline result and preserve the required Phase 3 query; any corrected version belongs in the optimized-query deliverable with the result difference explained.
6. **W04 and W05 are likely the heaviest writes.** W04 inserts invoices for many accounts; W05 checks invoice status and billing period while updating accounts.

After running the benchmark, replace the em dashes with measured values, update the scan notes from the actual plans, and revise the observations to describe measured results.
