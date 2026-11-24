# Phase 5 – Scalability Report

## 1. Scope and current evidence

This report addresses the Netflix streaming database’s Phase 5 requirements: run the optimized workload on the large dataset, compare growth with the optimized seed run, evaluate the query targets, report storage, and describe a 100× architecture.

The optimized seed summary and its 30 raw plans are present. The current workspace does **not** contain `large_data.zip`; `benchmarks/results/large/summary.csv` has no measured values and there are no large raw plans. Large-data timings, exact row counts, growth ratios, and storage are therefore pending. The project’s large-data figures below are estimates from its brief, not measurements.

## 2. Dataset and method

| Table | Seed rows | Large-data estimate from project brief |
|---|---:|---:|
| `accounts` | 25,000 | About 500,000 |
| `profiles` | 75,000 | About 1,500,000 |
| `viewing_activity` | 200,401 | About 4,008,000 |
| `invoices` | 133,057 | About 2,661,000 |
| Other CSV tables | See `README.md` | About 20× for larger tables; exact counts pending |

The project calls for three runs per optimized query with writes inside `BEGIN` / `ROLLBACK`. Do not run the original workload against the large database. The benchmark script writes average, median, minimum, maximum, and scan-node information to `benchmarks/results/large/summary.csv` and raw plans to the same directory.

Run after loading the large dataset, applying the current indexes, and running `ANALYZE`:

```bash
./benchmarks/run_benchmark.sh netflix_large large 3 sql/06_optimized_queries.sql
```

If a seed-specific identifier is absent in the large data, document the issue and keep any fixture-adjusted workload separate from `queries/workload_30.sql` and `sql/06_optimized_queries.sql`.

## 3. Large-data results and targets

The optimized seed averages below come from the current `benchmarks/results/optimized/summary.csv`. Large averages and growth are blank until a large-data run is measured. Targets follow the project brief.

| Query | Optimized seed (ms) | Optimized large (ms) | Growth | Large target | Status |
|---|---:|---:|---:|---:|---|
| R01 | 0.037 | — | — | < 5 ms | Pending large run |
| R02 | 0.035 | — | — | < 5 ms | Pending large run |
| R03 | 0.476 | — | — | < 250 ms | Pending large run |
| R04 | 0.368 | — | — | < 250 ms | Pending large run |
| R05 | 0.173 | — | — | < 250 ms | Pending large run |
| R06 | 0.044 | — | — | < 5 ms | Pending large run |
| R07 | 0.019 | — | — | < 5 ms | Pending large run |
| R08 | 1.659 | — | — | < 5,000 ms | Pending large run |
| R09 | 12.597 | — | — | < 5,000 ms | Pending large run |
| R10 | 0.028 | — | — | < 5 ms | Pending large run |
| R11 | 2.607 | — | — | < 250 ms | Pending large run |
| R12 | 0.500 | — | — | < 5,000 ms | Pending large run |
| R13 | 0.062 | — | — | < 250 ms | Pending large run |
| R14 | 19.388 | — | — | < 5,000 ms | Pending large run |
| R15 | 4.082 | — | — | < 5,000 ms | Pending large run |
| R16 | 119.792 | — | — | < 5,000 ms | Pending large run |
| R17 | 4.861 | — | — | < 5,000 ms | Pending large run |
| R18 | 15.983 | — | — | < 5,000 ms | Pending large run |
| R19 | 3.890 | — | — | < 5,000 ms | Pending large run |
| R20 | 1.233 | — | — | < 5,000 ms | Pending large run |
| R21 | 0.272 | — | — | < 250 ms | Pending large run |
| R22 | 0.066 | — | — | < 250 ms | Pending large run |
| R23 | 12.926 | — | — | < 250 ms | Pending large run |
| R24 | 0.027 | — | — | < 5 ms | Pending large run |
| R25 | 0.446 | — | — | < 250 ms | Pending large run |
| W01 | 0.790 | — | — | < 5 ms | Pending large run |
| W02 | 0.601 | — | — | < 5 ms | Pending large run |
| W03 | 0.340 | — | — | < 5 ms | Pending large run |
| W04 | 157.011 | — | — | < 2,000 ms | Pending large run |
| W05 | 7.739 | — | — | < 2,000 ms | Pending large run |

**Target grouping:** real-time/member-facing queries R01, R02, R06, R07, R10, R24, W01, W02, and W03 have a 5 ms target. Interactive queries R03, R04, R05, R11, R13, R21, R22, R23, and R25 have a 250 ms target. Analytics queries R08, R09, R12, R14–R20 have a 5,000 ms target. Batch writes W04 and W05 have a 2,000 ms target.

Calculate growth as `optimized large avg ÷ optimized seed avg`. The growth classifications and whether targets are met cannot be reported until the large averages are populated.

## 4. Growth analysis to complete from plans

The following are workload-based hypotheses, not measured large-data results:

| Query pattern | Queries | What to check as data grows |
|---|---|---|
| Selective profile/title/account lookups | R01, R02, R06, R07, R10, R24 | Confirm that the plan keeps using selective indexes and that rows visited remain small. |
| Time-window and status filters | R03, R04, R05, R11, R13, R21, R22, R25 | Compare qualifying-row fractions, index conditions, and heap fetches; selectivity may change at scale. |
| Full-history and multi-table aggregates | R08, R09, R14, R15, R16, R17, R18, R19, R20 | Record rows scanned, join strategy, hash/sort spills, temp buffers, and whether an index is cheaper than a sequential scan. |
| Deep pagination | R23 | Measure index walk cost for `OFFSET 150000`; an ordering index does not remove the skipped-row work. |
| Batch writes | W04, W05 | Record inserted/updated row counts, index maintenance, foreign-key trigger time, and buffers dirtied. |

Use actual plans to classify queries as roughly flat, proportional to data growth, or superlinear. For any target miss, show the before/after plan and benchmark the fix with the same data and rollback method.

## 5. Likely scale risks

- **R16** groups viewing activity by account and hour and counts distinct profiles. It is a broad aggregation and may need a summary table or pre-aggregation if the measured plan exceeds its target.
- **R09 and R18** aggregate activity by genre or device/month. Their cost depends on the number of qualifying rows; compare a timestamp index scan with a sequential scan.
- **R23** uses deep `OFFSET` pagination. Consider keyset pagination only with a defined cursor and an approved workload that preserves the support console’s ordering.
- **W04** inserts a large invoice batch. Measure source selection, foreign-key checks, and all index maintenance before considering batching or other changes.
- **R19** is fast on the seed benchmark with a title/time index. Confirm its plan and cost on the large data rather than extrapolating from seed timing.

These are investigation areas, not confirmed failures; no large plans are currently available.

## 6. Storage

Seed and large database sizes have not been measured in the current workspace. After loading, indexing, and running `ANALYZE`, collect the following on both databases:

```sql
SELECT current_database() AS database_name,
       pg_size_pretty(pg_database_size(current_database())) AS database_size;

SELECT c.relname AS relation_name,
       pg_size_pretty(pg_table_size(c.oid)) AS table_size,
       pg_size_pretty(pg_indexes_size(c.oid)) AS index_size,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'netflix'
  AND c.relkind IN ('r', 'p')
ORDER BY pg_total_relation_size(c.oid) DESC;
```

When adding relation sizes, avoid counting a partitioned parent and its child partitions twice. State whether the partitioned copy and its indexes are included.

## 7. Architecture for 100×

### 7.1 Monthly partitioning

Monthly `RANGE` partitions on `viewing_activity.started_at` are a reasonable candidate: the workload includes time-window queries, and partition detach/archive operations can simplify retention. The proposed side-by-side design is in `sql/08_partitioning.sql`; it leaves the original table intact, creates monthly partitions and a default partition, copies rows, builds partition-aware indexes, runs `ANALYZE`, and contains row-equivalence and pruning checks.

The script has not been executed in the current environment. Run it against a loaded database, retain both `EXCEPT ALL` counts, and capture the June `EXPLAIN` plan before claiming pruning or row equivalence. PostgreSQL requires a partitioned primary/unique key to include the partition key; the proposed `(view_id, started_at)` key therefore does not guarantee global uniqueness of `view_id`. Production cutover needs a global ID allocator or registry.

### 7.2 Sharding

Account-based sharding is the first candidate because accounts own profiles and billing/settings operations are account-scoped. The current viewing rows contain `profile_id`, so routing requires a reliable profile-to-account directory or an account routing key with an enforced profile/account relationship.

Under account sharding, global reports such as R03, R09, R17, R19, and R20 become cross-shard. Each shard can compute partial counts, sums, maxima, or grouped values for a coordinator to merge. R16 can remain local to an account if all its profiles are colocated, but still processes that account’s history. Profile sharding simplifies R01 but may split households; title sharding helps title reports but scatters household activity.

### 7.3 Read replicas and caching

| Workload | Suggested route | Consideration |
|---|---|---|
| R01, R06, R24 | Primary for strict freshness; replica if bounded lag is acceptable | Play and list/profile state can change immediately. |
| R10 and account settings | Primary | Identity and account status should be current. |
| W01–W05 | Primary | These are transactional writes. |
| R03, R08, R09, R12, R14–R20 | Analytics/read replica when lag is acceptable | Isolates reporting from transactional traffic. |
| R04, R05, R11, R13, R21–R23, R25 | Replica or cache only if freshness permits | Payment retry and compliance results may need primary freshness. |

Cache catalogue and search results only with explicit TTL and invalidation rules. Avoid caching billing state, account status, or compliance decisions without an approved freshness policy.

### 7.4 Maintenance and retention

- Keep autovacuum enabled and monitor dead tuples, vacuum lag, and partition statistics before changing settings.
- Run `ANALYZE` after bulk loads and partition creation/attachment.
- Create future monthly partitions before their first write and monitor the default partition.
- Agree on retention and legal requirements before detaching or dropping old partitions.
- Schedule and expose freshness for any future summary or materialized views.
- Monitor index size and write overhead; partitioning does not replace indexes or vacuuming.

## 8. Conclusion

The seed optimized workload is measured and its raw plans are available. Large-data readiness is not yet established: the large archive and measured large results are absent. Restore the large dataset, run all 30 optimized queries three times, capture plans and storage, complete the target/growth table, and validate `sql/08_partitioning.sql` before making a scalability claim.
