-- verify.sql
-- CIT 408 · Assignment 3.2 · Proof of the point-in-time recovery.
-- Run twice on the recovered server: while recovery is paused (read-only), and after it finishes.
--   dpsql -d drill < verify.sql
-- All times are shown in UTC with an explicit +00:00 offset.

SET TIME ZONE 'UTC';

-- V1. Where the server is: still paused in recovery, or promoted
SELECT pg_is_in_recovery()                  AS in_recovery,
       CASE WHEN pg_is_in_recovery() THEN pg_get_wal_replay_pause_state() ELSE 'promoted' END AS state,
       to_char(now(), 'YYYY-MM-DD HH24:MI:SS TZH:TZM') AS checked_at;

-- V2. The last transaction replayed, and when it committed
SELECT to_char(pg_last_xact_replay_timestamp(), 'YYYY-MM-DD HH24:MI:SS.US TZH:TZM') AS last_replayed_commit;

-- V3. Exact row count of every table in the drill schema
SELECT table_name,
       (xpath('/row/c/text()',
              query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text::int AS row_count
FROM information_schema.tables
WHERE table_schema = 'drill' AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- V4. Every batch present after recovery (compare with evidence/activity_before.csv)
SELECT * FROM drill.activity ORDER BY 1;

-- V5. The damage is gone: drill.customer exists again with all 500 customers
SELECT to_regclass('drill.customer') AS customer_table, (SELECT count(*) FROM drill.customer) AS customers;

-- V6. The foreign key that DROP ... CASCADE removed is back on drill.dispatch
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'drill.dispatch'::regclass AND contype = 'f';

-- V7. Batches 1-8 (committed before the incident) are present; batches 9-14 (after it) are not
SELECT count(*) FILTER (WHERE batch_no BETWEEN 1 AND 8)  AS batches_before_incident_present,
       count(*) FILTER (WHERE batch_no BETWEEN 9 AND 14) AS batches_after_incident_present,
       max(batch_no) AS last_batch
FROM drill.activity;

-- V8. Dispatches and lines: 20,000 + 8 x 150 = 21,200 dispatches; 50,000 + 8 x 300 = 52,400 lines
SELECT (SELECT count(*) FROM drill.dispatch)      AS dispatches,
       (SELECT count(*) FROM drill.dispatch_line) AS dispatch_lines,
       (SELECT count(*) FROM drill.dispatch WHERE batch_no >= 9) AS dispatches_from_lost_batches;
