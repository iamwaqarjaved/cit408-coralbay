# Incident report: customer table dropped from the dispatch database

**System:** Coral Bay dispatch database (`drill`), PostgreSQL 17
**Date:** 21 October 2026
**Prepared by:** Waqar Javed, DBA on call
**Status:** Resolved. The database was recovered to the last good moment, and archiving and backups are healthy again.

## Summary

At **06:57:11 UTC** (02:57:11 Eastern), someone ran a command that deleted the entire **customer** table: all 500 customers. The same command removed the rule linking each dispatch to its customer. Dispatch work kept arriving for the next five minutes, so six more batches were saved on top of the damage.

I restored the database to **06:56:58 UTC**, the moment the last good batch (batch 8) finished. That is 13 seconds before the deletion. All 500 customers and the customer link are back, and every batch from before the deletion is intact.

Six batches that arrived after the deletion (batches 9–14, **900 dispatches and 1,800 dispatch lines**) are no longer in the live database. I saved a full copy of them before recovering, so they can be loaded back rather than retyped. The database was unavailable for about 25 minutes while I restored and checked it.

All times below are written with their offset. **UTC is +00:00.** Coral Bay's local time is Eastern Daylight Time, **−04:00**, so subtract four hours from UTC.

## 1. Timeline

| Event | UTC (+00:00) | Eastern (−04:00) | Source |
|---|---|---|---|
| Base backup `base_20261021T065059Z` started | 2026-10-21 06:50:59 +00:00 | 02:50:59 −04:00 | `backup_label` |
| Base backup finished and verified | 2026-10-21 06:51:10 +00:00 | 02:51:10 −04:00 | `pg_verifybackup` |
| Dispatch workload started (batch 1) | 2026-10-21 06:52:35 +00:00 | 02:52:35 −04:00 | workload output |
| Last good batch (batch 8) committed, transaction 812 | 2026-10-21 06:56:58.492920 +00:00 | 02:56:58 −04:00 | WAL commit record |
| **Incident:** `DROP TABLE drill.customer CASCADE` committed, transaction 813 | **2026-10-21 06:57:11.606275 +00:00** | **02:57:11 −04:00** | WAL commit record, server log |
| Batches 9–14 kept arriving on the damaged database | 06:57:59 to 07:01:32 +00:00 | 02:57:59 to 03:01:32 −04:00 | `drill.activity` |
| Workload finished | 2026-10-21 07:02:00 +00:00 | 03:02:00 −04:00 | workload output |
| **Detection:** investigation started | **2026-10-21 07:02:43 +00:00** | **03:02:43 −04:00** | my log |
| **Recovery started:** damaged server stopped and kept | **2026-10-21 07:20:53 +00:00** | **03:20:53 −04:00** | my log |
| Recovery attempt 1 paused before transaction 813 | 2026-10-21 07:21:52 +00:00 | 03:21:52 −04:00 | server log |
| Recovery attempt 2 paused after transaction 812, then checked | 2026-10-21 07:42:49 +00:00 | 03:42:49 −04:00 | server log |
| **Recovery finished:** new timeline 2, open for work | **2026-10-21 07:46:13 +00:00** | **03:46:13 −04:00** | server log, my log |
| Fresh base backup `base_20261021T074614Z` finished and verified | 2026-10-21 07:46:14 +00:00 | 03:46:14 −04:00 | `pg_verifybackup` |

## 2. What happened, and how I know

**What was damaged.** The `drill.customer` table was deleted outright. That removed all 500 customers, their primary key, and, because of `CASCADE`, the foreign key from `dispatch` to `customer`. Dispatches and dispatch lines were not deleted, but they no longer pointed to any customer. Nothing else in the database showed any updates or deletes (`evidence/03_table_activity.txt`).

I confirmed it from four independent sources before changing anything.

**1. The server log records the command and its time** (`evidence/06_suspicious_statements.txt`):
```
2026-10-21 06:57:11.600 UTC [138] postgres@drill LOG:  statement: DROP TABLE drill.customer CASCADE;
```
It came from the same session (process 138) that was running the dispatch batches. It sits between batch 8 (06:56:58) and batch 9 (06:57:59).

**2. The write-ahead log gives the exact transaction and commit time** (`evidence/10_truncate_drop.txt`, from `pg_waldump`):
```
rmgr: Transaction ... tx: 813, lsn: 0/0A00FA58 ... desc: COMMIT 2026-10-21 06:57:11.606275 UTC;
      rels: base/16388/16390 base/16388/16393; dropped stats: 2/16388/16393 2/16388/16390
```
The `rels:` list means this commit deleted two files from disk: the customer table and its primary key index. It is the only commit in the whole drill that removed files.

**3. The order of commits puts transaction 813 between two good batches** (`evidence/12_all_commits.txt`):
```
812  2026-10-21 06:56:58.492920 UTC   <- batch 8, last good work
813  2026-10-21 06:57:11.606275 UTC   <- the DROP
814  2026-10-21 06:57:59.943323 UTC   <- batch 9, first batch on damaged data
```

**4. The live database showed the damage** (`evidence/13_damage.txt`). `to_regclass('drill.customer')` returned nothing, and the description of `drill.dispatch` no longer listed any foreign key to a customer.

Two other entries looked suspicious and were ruled out:
- **`DROP SCHEMA … CASCADE` at 06:50:06.** This came from the setup script, before the base backup.
- **Transaction 820 at 07:02:36.** It came after the workload ended and wrote only five small records: routine background maintenance.

## 3. The recovery target, and why it is the right one

**Target chosen: stop right after transaction 812** (`recovery_target_xid = '812'`, `recovery_target_inclusive = on`). That is the commit of batch 8 at **2026-10-21 06:56:58.492920 +00:00**.

- **It loses nothing good.** No other work committed between transaction 812 and the DROP, so stopping after 812 keeps every change made before the incident.
- **It excludes the damage.** Replay stops 13 seconds before the DROP commits.
- **It avoids the time-zone trap.** A transaction ID is the same in every tool. Times are not: during the drill, the same instant appeared as 06:57:11 UTC in one tool and 02:57:11 EDT in another. A time typed in the wrong zone would have restored to four hours earlier or later.

**Why there were two attempts.** My first attempt targeted "just before transaction 813". It stopped in the right place: the log says `recovery stopping before commit of transaction 813, time 2026-10-21 06:57:11.606275+00`, and batches 1–8 were present. But while recovery was paused, any query on the customer or dispatch tables hung. The DROP had already locked those tables a moment before its commit, and the paused recovery was still holding that lock (`evidence/15_paused_lock.txt` shows `AccessExclusiveLock` on `customer`, `customer_pkey` and `dispatch`). I couldn't check the data, so I discarded that attempt and recovered again to "just after transaction 812". This gives an identical result, but stops before the DROP takes its lock. I never finished a recovery I hadn't checked. The damaged data directory was kept throughout (container `drill_damaged`, volume `drill_data`).

**Checked while paused, before finishing** (`verify_paused.txt`):

| Check | Result |
|---|---|
| Recovery log | `recovery stopping after commit of transaction 812, time 2026-10-21 06:56:58.49292+00` |
| Last replayed commit | 2026-10-21 06:56:58.492920 +00:00 |
| `drill.customer` | Present, 500 rows |
| Foreign key `dispatch_customer_id_fkey` | Present |
| Batches 1–8 | All 8 present, commit times identical to the evidence |
| Batches 9–14 | 0 present |
| Dispatches / lines | 21,200 / 52,400 (20,000 + 8 × 150 and 50,000 + 8 × 300) |

The same checks gave the same results after recovery finished (`verify_after.txt`).

## 4. What was lost, and how to get it back

Six batches committed after the incident and are not in the recovered database. The `diff` between the batch list saved before recovery and the list after recovery names exactly these six (`lost_batches.txt`):

| Batch | Committed (UTC) | Committed (Eastern) | Dispatches | Lines |
|---|---|---|---|---|
| 9 | 06:57:59.94 +00:00 | 02:57:59 −04:00 | 150 | 300 |
| 10 | 06:58:40.95 +00:00 | 02:58:40 −04:00 | 150 | 300 |
| 11 | 06:59:15.15 +00:00 | 02:59:15 −04:00 | 150 | 300 |
| 12 | 06:59:58.63 +00:00 | 02:59:58 −04:00 | 150 | 300 |
| 13 | 07:00:45.79 +00:00 | 03:00:45 −04:00 | 150 | 300 |
| 14 | 07:01:32.32 +00:00 | 03:01:32 −04:00 | 150 | 300 |
| **Total** | | | **900** | **1,800** |

**How the business re-enters them.** Nobody has to retype them. Before recovering, I exported all of these rows from the damaged database:
- `evidence/lost_dispatch.csv` (900 dispatches)
- `evidence/lost_dispatch_line.csv` (1,800 lines)
- `evidence/lost_activity.csv` (6 batch records)

The customer table is back and every customer these dispatches refer to still exists, so the rows can be loaded back in the order batch, dispatches, lines, after the dispatch team confirms they are still wanted. If they would rather re-key the work, the batch numbers and times above tell them exactly what to look for.

## 5. RPO and RTO achieved

| Measure | Achieved | What it means |
|---|---|---|
| **RPO (data lost)** | **0 seconds of good work before the incident.** The recovery point is 13 seconds before the DROP. | Everything committed before the mistake was saved. The only work missing is what arrived after it: 4 min 21 s of batches (06:57:11 to 07:01:32 UTC), and that was exported and can be reloaded. |
| **RTO (time to recover)** | **25 min 20 s** of downtime (07:20:53 to 07:46:13 UTC). **43 min 30 s** from detection to service restored (07:02:43 to 07:46:13 UTC). | Most of it was investigation and checking, including one restart. The WAL replay itself took under one second. |

## 6. Changes to stop this happening, or catch it sooner

1. **Separate the application's login from the table owner.** The command ran as `postgres`, a superuser that can drop anything. The dispatch application should use a role that can insert, update and select but doesn't own the tables, so `DROP TABLE` fails with "permission denied". Schema changes would then go through a separate admin login, used only during planned changes.
2. **Block dangerous commands with an event trigger.** A small `ddl_command_start` trigger can refuse `DROP TABLE` on the dispatch schema unless a maintenance flag is set first. This stops a mistake even when it is made by an account with high privileges.
3. **Alert on destructive commands within seconds.** We already log every data-changing statement. Sending any `DROP`, `TRUNCATE`, or `DELETE` without a `WHERE` clause to an alert channel would have flagged this at 06:57:11 instead of 07:02:43, and five fewer batches would have been written on top of the damage.
4. **Keep a delayed standby replica.** A replica that applies changes 30 minutes behind production (`recovery_min_apply_delay = '30min'`) would still have the customer table when the mistake is noticed. Recovery would then take minutes instead of a full restore from the base backup.
5. **Practise this drill regularly.** This drill showed that a paused recovery can hold the incident's own lock. Knowing that in advance would have saved one restart (about 20 minutes).

## Evidence index

All files are in `evidence/` and were saved before recovery unless marked otherwise.

| File | Contents |
|---|---|
| `00_base_backup.txt` | Both base backups: folder, finish time and `backup_label` |
| `01_workload_times.txt` | Workload, detection and recovery times (UTC) |
| `02_workload_output.txt` | Script output, batches 1–14 |
| `03_table_activity.txt` · `04_relfilenodes.txt` | Per-table activity; file-number map (no customer table) |
| `05_server_log_full.txt` · `06_suspicious_statements.txt` | Full server log; the DROP statements |
| `08`–`12_*.txt` | pg_waldump analysis: records per transaction, updates and deletes, dropped files, all commits |
| `13_damage.txt` | Customer table missing; foreign key gone |
| `activity_before.csv` · `lost_*.csv` | All 14 batches before recovery; full export of the lost batches |
| `14_recovery_log*.txt` · `15_paused_lock.txt` | Recovery log lines for both attempts; the lock that blocked attempt 1 (during recovery) |
