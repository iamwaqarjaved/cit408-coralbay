# Assignment 3.2: Recovery drill, every command in order

**Server:** PostgreSQL 17 in a Docker container on my MacBook. Point-in-time recovery needs control of the server itself (archive settings, the data directory, restarting into recovery). Supabase doesn't give that, so the drill runs on a server I own.

**Storage:** four Docker volumes:

| Volume | Holds |
|---|---|
| `drill_data` | The original data directory. After the incident, it is kept untouched as the damaged copy. |
| `drill_archive` | Archived WAL files |
| `drill_backups` | Base backups |
| `drill_recovered` | The recovered data directory |

**Time zone:** the container runs in UTC (`TZ=UTC`), and the server log, psql and pg_waldump all print UTC. My Mac is on EDT (UTC−04:00). Every time I record is written with an explicit offset.

**Working folder on my Mac:** `~/cit408-drill`, which holds the scripts, `evidence/` and outputs.

Run each block in macOS Terminal (zsh). Each command has a one-line explanation under it.

---

## Step 0. Prepare the Mac

```bash
mkdir -p ~/cit408-drill/evidence && cd ~/cit408-drill
```
Creates the working folder and the evidence folder.

```bash
cp ~/Downloads/w3_drill_setup.sql ~/Downloads/w3_drill_incident.sql ~/cit408-drill/
```
Puts the two course scripts in the working folder. They are not edited.

```bash
dpsql() { docker exec -i -u postgres drill psql -X "$@"; }
dsh()   { docker exec -i -u postgres drill bash -c "$1"; }
```
Two shortcuts for this Terminal window. `dpsql` runs psql inside the container, and `dsh` runs a shell command there as the postgres user. Re-run them in any new Terminal window.

```bash
utc() { date -u "+%Y-%m-%d %H:%M:%S +00:00"; }
```
Prints the current time in UTC with an explicit offset. I use it to stamp every timeline event.

## Step 1. Start the server with continuous WAL archiving

```bash
docker volume create drill_data; docker volume create drill_archive; docker volume create drill_backups
```
Creates the volumes for the data directory, the WAL archive and the base backups.

```bash
docker run -d --name drill -e POSTGRES_PASSWORD=drill -e TZ=UTC \
  -v drill_data:/var/lib/postgresql/data -v drill_archive:/archive -v drill_backups:/backups \
  postgres:17
```
Starts PostgreSQL 17 with all three volumes mounted. `TZ=UTC` fixes the container clock zone.

```bash
docker exec -u root drill chown postgres:postgres /archive /backups
```
Lets the postgres user write to the archive and backup folders.

```bash
dpsql <<'SQL'
ALTER SYSTEM SET archive_mode = on;
ALTER SYSTEM SET archive_command = 'test ! -f /archive/%f && cp %p /archive/%f';
ALTER SYSTEM SET archive_timeout = 60;
ALTER SYSTEM SET track_commit_timestamp = on;
ALTER SYSTEM SET log_statement = 'mod';
ALTER SYSTEM SET log_line_prefix = '%m [%p] %u@%d ';
ALTER SYSTEM SET timezone = 'UTC';
ALTER SYSTEM SET log_timezone = 'UTC';
SQL
```
These settings are saved in `postgresql.auto.conf`, so every base backup carries them:
- **archive_mode, archive_command:** copy every finished WAL file to `/archive`, and never overwrite an existing file.
- **archive_timeout = 60:** forces a WAL switch at least once a minute, even when the server is quiet.
- **track_commit_timestamp:** records each transaction's commit time.
- **log_statement = 'mod':** writes every data-changing statement to the log with a timestamp. This is my first piece of evidence.
- **timezone, log_timezone:** make psql output and the log both show UTC.

```bash
docker restart drill && sleep 5
```
`archive_mode` and `track_commit_timestamp` only take effect after a restart.

```bash
dpsql -c "SHOW archive_mode" -c "SHOW archive_command" -c "SHOW archive_timeout" -c "SHOW track_commit_timestamp"
```
Confirms the settings are live.

```bash
dpsql -c "SELECT pg_switch_wal();" && sleep 70
dpsql -c "SELECT archived_count, last_archived_wal, last_archived_time, failed_count, last_failed_wal FROM pg_stat_archiver;"
```
Forces one WAL switch, then waits past `archive_timeout`. **📸 Screenshot `01_pg_stat_archiver.png`:** `archived_count` above 0 and `failed_count` = 0.

```bash
dsh "ls -l /archive"
```
Shows the archived WAL files on disk.

## Step 2. Create the drill database

```bash
dpsql -c "CREATE DATABASE drill;"
dpsql -d drill -v ON_ERROR_STOP=1 < w3_drill_setup.sql
```
Creates the `drill` database and runs the course setup script in it.

```bash
dpsql -d drill -c "\dt drill.*"
```
Lists the tables the setup created.

## Step 3. Base backup, verified

```bash
export BASE=base_$(date -u +%Y%m%dT%H%M%SZ)
dsh "pg_basebackup -D /backups/$BASE -Fp -Xs -c fast -P -v"
```
Takes a plain-format base backup of the whole server, with the WAL it needs included (`-Xs`). The folder name carries the UTC time.

```bash
dsh "pg_verifybackup /backups/$BASE" && echo "BASE BACKUP $BASE finished at $(utc)" | tee evidence/00_base_backup.txt
```
Checks every file against the backup manifest, then records the folder name and finish time.

```bash
dsh "cat /backups/$BASE/backup_label" | tee -a evidence/00_base_backup.txt
```
Saves `backup_label`. Its `START WAL LOCATION` is where pg_waldump starts reading later.

## Step 4. Run the workload (do not touch it)

```bash
echo "WORKLOAD START $(utc)" | tee evidence/01_workload_times.txt
dpsql -d drill < w3_drill_incident.sql 2>&1 | tee evidence/02_workload_output.txt
echo "WORKLOAD END $(utc)" | tee -a evidence/01_workload_times.txt
```
Runs the course script unchanged and saves everything it prints. Leave it running until it prints `Workload finished` (about 10 minutes).

## Step 5. Investigate before changing anything (save all evidence)

```bash
echo "DETECTION / INVESTIGATION START $(utc)" | tee -a evidence/01_workload_times.txt
```
Records when I started looking. This is the detection time for the report.

```bash
dpsql -d drill -c "\copy (SELECT * FROM drill.activity ORDER BY 1) TO STDOUT CSV HEADER" > evidence/activity_before.csv
cat evidence/activity_before.csv
```
Saves every committed batch, as the assignment requires. After recovery, comparing this file with the recovered table gives the exact list of lost batches.

```bash
dpsql -d drill -c "SELECT relname, n_live_tup, n_tup_ins, n_tup_upd, n_tup_del FROM pg_stat_user_tables WHERE schemaname = 'drill' ORDER BY relname;" | tee evidence/03_table_activity.txt
```
Row activity per table. A mass UPDATE or DELETE shows up as a sudden spike in `n_tup_upd` or `n_tup_del`, and a dropped table is simply missing from the list.

```bash
dpsql -d drill -c "SELECT c.oid, c.relfilenode, c.relname FROM pg_class c WHERE c.relnamespace = 'drill'::regnamespace ORDER BY 3;" | tee evidence/04_relfilenodes.txt
```
Maps file numbers to table names. pg_waldump names tables by file number, not by name.

```bash
docker logs drill > evidence/05_server_log_full.txt 2>&1
grep -nE "statement: (DELETE|UPDATE|TRUNCATE|DROP|ALTER)" evidence/05_server_log_full.txt | tee evidence/06_suspicious_statements.txt
```
Saves the full server log, then pulls out every destructive-looking statement with its UTC timestamp. `log_statement = 'mod'` captured the statement text.

```bash
dpsql -c "SELECT pg_switch_wal();" && sleep 5
```
Closes the current WAL file so that the incident's WAL is in the archive. This writes no data.

```bash
export START_LSN=$(dsh "grep 'START WAL LOCATION' /backups/$BASE/backup_label" | awk '{print $4}')
echo $START_LSN
dsh "pg_waldump -p /archive -s $START_LSN 2>&1" > evidence/07_waldump_full.txt
```
Decodes every WAL record since the base backup into a text file. The final "could not find file" line only marks the end of the archive and is expected. pg_waldump runs inside the container, so its timestamps are in UTC.

```bash
grep -o 'tx: *[0-9]*' evidence/07_waldump_full.txt | awk '$2 != 0 {print $2}' | sort | uniq -c | sort -rn | head -10 | tee evidence/08_records_per_xid.txt
```
Counts WAL records per transaction ID. Normal batches are small, so the incident usually stands out as one transaction with far more records.

```bash
grep -E "rmgr: Heap2? .*desc: (UPDATE|HOT_UPDATE|DELETE)" evidence/07_waldump_full.txt | grep -o 'tx: *[0-9]*' | sort | uniq -c | sort -rn | head | tee evidence/09_update_delete_by_xid.txt
grep -E "desc: TRUNCATE|rels:" evidence/07_waldump_full.txt | tee evidence/10_truncate_drop.txt
```
Shows which transactions changed or deleted rows, and any TRUNCATE or DROP. A DROP appears as a `COMMIT … rels:` record that lists the removed files.

```bash
export BAD_XID=813    # found above: DROP TABLE drill.customer CASCADE, committed 2026-10-21 06:57:11.606275 +00:00
grep -E "tx: *$BAD_XID," evidence/07_waldump_full.txt | grep "desc: COMMIT" | tee evidence/11_incident_commit.txt
grep -E "desc: COMMIT" evidence/07_waldump_full.txt | sed 's/.*tx: *\([0-9]*\),.*COMMIT \([^;]*\).*/\1  \2/' > evidence/12_all_commits.txt
grep -n -B3 -A3 "^$BAD_XID " evidence/12_all_commits.txt
```
Saves the incident's exact COMMIT record (transaction ID and commit time, to the microsecond, in UTC), plus the commits just before and after it.

```bash
dpsql -d drill -c "SELECT to_regclass('drill.customer') AS customer_table;" -c "\d drill.dispatch" > evidence/13_damage.txt
```
Shows the damage in the live data: the customer table no longer exists (NULL), and dispatch has lost its foreign key to customer.

```bash
for t in dispatch activity; do dpsql -d drill -c "\copy (SELECT * FROM drill.$t WHERE batch_no >= 9 ORDER BY 1) TO STDOUT CSV HEADER" > evidence/lost_$t.csv; done
dpsql -d drill -c "\copy (SELECT l.* FROM drill.dispatch_line l JOIN drill.dispatch d USING (dispatch_id) WHERE d.batch_no >= 9 ORDER BY 1,2) TO STDOUT CSV HEADER" > evidence/lost_dispatch_line.csv
wc -l evidence/lost_*.csv
```
Exports the work that committed after the incident (batches 9–14: 900 dispatches, 1,800 lines). Recovery will remove these rows, and this copy lets the business reload them instead of retyping.

## Step 6. Recover to just before the incident

```bash
echo "RECOVERY START $(utc)" | tee -a evidence/01_workload_times.txt
docker stop drill && docker rename drill drill_damaged
```
Stops the damaged server and keeps it: the container `drill_damaged` and its volume `drill_data` are never deleted. Stopping it also archives the last WAL file.

```bash
docker volume create drill_recovered
docker run --rm -u root -e BASE=$BASE -v drill_backups:/backups -v drill_recovered:/data postgres:17 \
  bash -c 'cp -a /backups/$BASE/. /data/ && chown -R postgres:postgres /data && chmod 700 /data'
```
Copies the base backup into a new, empty data directory.

```bash
cat > recovery_settings.conf <<EOF
restore_command = 'cp /archive/%f %p'
recovery_target_xid = '$BAD_XID'
recovery_target_inclusive = off
recovery_target_action = 'pause'
EOF
cat recovery_settings.conf
```
Writes the recovery settings:
- **restore_command:** fetches WAL from the archive.
- **recovery_target_xid** with **recovery_target_inclusive = off:** replay stops just before the incident transaction commits. Every transaction that committed before it is replayed.
- **recovery_target_action = 'pause':** holds the database read-only at that point, so I can check it before finishing.

```bash
docker run --rm -u root -v drill_recovered:/data -v "$PWD":/host postgres:17 \
  bash -c 'cat /host/recovery_settings.conf >> /data/postgresql.auto.conf && touch /data/recovery.signal && chown postgres:postgres /data/recovery.signal /data/postgresql.auto.conf'
```
Adds the settings to the recovered directory and creates `recovery.signal`, which tells PostgreSQL to start in targeted recovery.

```bash
docker run -d --name drill -e POSTGRES_PASSWORD=drill -e TZ=UTC \
  -v drill_recovered:/var/lib/postgresql/data -v drill_archive:/archive -v drill_backups:/backups \
  postgres:17 && sleep 10
```
Starts a new server named `drill` on the recovered directory. It replays WAL and pauses at the target.

```bash
docker logs drill 2>&1 | grep -E "point-in-time|restored log file|consistent|recovery stopping|pausing|pg_wal_replay_resume" | tee evidence/14_recovery_log.txt
```
Shows the recovery in the server log. **📸 Screenshot `02_recovery_log.png`:** `starting point-in-time recovery to XID …`, the restored log files, `recovery stopping before commit of transaction …, time …`, and `pausing at the end of recovery`.

## Step 6b. Second attempt: stop after transaction 812

The first attempt stopped correctly ("recovery stopping before commit of transaction 813"), but every query on `customer` or `dispatch` hung while paused. The DROP takes an `AccessExclusiveLock` a moment before it commits, and a recovery paused before that commit still holds the lock.

```bash
dpsql -d drill -c "SELECT locktype, relation::regclass AS rel, mode, granted, pid FROM pg_locks WHERE mode = 'AccessExclusiveLock';" | tee evidence/15_paused_lock.txt
```
Proves the cause: the paused recovery process holds `AccessExclusiveLock` on `customer`, `customer_pkey` and `dispatch`. I pressed Ctrl-C on the hung query first.

```bash
docker stop drill && docker rm drill && docker volume rm drill_recovered
```
Discards attempt 1. The damaged server, `drill_damaged` with volume `drill_data`, is not touched.

Then I repeated Step 6 with these settings in `recovery_settings.conf`:
```
restore_command = 'cp /archive/%f %p'
recovery_target_xid = '812'
recovery_target_inclusive = on
recovery_target_action = 'pause'
```
Transaction 812 is batch 8, the last commit before the DROP; no other transaction committed in between. Stopping *after* 812 gives exactly the same data, but stops before the DROP takes its lock. The log said `recovery stopping after commit of transaction 812, time 2026-10-21 06:56:58.49292+00`. I saved it to `evidence/14_recovery_log_attempt2.txt` and took screenshot `02_recovery_log.png`.

## Step 7. Check while paused (restart if wrong)

Results: paused at 06:56:58.492920 +00:00; customer back with 500 rows; foreign key restored; batches 1–8 present and 9–14 absent; 21,200 dispatches and 52,400 lines. The diff listed exactly batches 9–14.

```bash
dpsql -d drill < verify.sql | tee verify_paused.txt
dpsql -d drill -c "\copy (SELECT * FROM drill.activity ORDER BY 1) TO STDOUT CSV HEADER" > activity_after.csv
diff evidence/activity_before.csv activity_after.csv | tee lost_batches.txt
```
Runs the checks on the paused, read-only database. The `diff` lists exactly the batches that are in the evidence but not in the recovered data: those are the lost batches. All of them must have committed after the incident.

**If the damage is still there, or a good batch is missing:**
```bash
docker stop drill && docker rm drill && docker volume rm drill_recovered
```
Discards this attempt. Then repeat Step 6 with a corrected target, for example the previous transaction ID, or `recovery_target_time = '<commit time> +00:00'`.

## Step 8. Finish recovery and clean up

```bash
dpsql -c "SELECT pg_wal_replay_resume();" && sleep 5
dpsql -c "SELECT pg_is_in_recovery();"
echo "RECOVERY END $(utc)" | tee -a evidence/01_workload_times.txt
```
Ends recovery. The server picks a new timeline and opens for writes (`pg_is_in_recovery` = `f`).

```bash
docker logs drill 2>&1 | grep -E "selected new timeline|archive recovery complete|ready to accept connections" | tee -a evidence/14_recovery_log.txt
```
Records the end of recovery in the log.

```bash
dpsql <<'SQL'
ALTER SYSTEM RESET restore_command;
ALTER SYSTEM RESET recovery_target_xid;
ALTER SYSTEM RESET recovery_target_inclusive;
ALTER SYSTEM RESET recovery_target_action;
SELECT pg_reload_conf();
SQL
dsh "grep -c recovery_target /var/lib/postgresql/data/postgresql.auto.conf; ls /var/lib/postgresql/data/recovery.signal"
```
Removes the recovery settings. The check prints `0`, and "No such file" for `recovery.signal`, which PostgreSQL deletes itself when recovery ends.

```bash
dpsql -d drill < verify.sql | tee verify_after.txt
```
Final verification on the live, recovered database.

```bash
export NEWBASE=base_$(date -u +%Y%m%dT%H%M%SZ)
dsh "pg_basebackup -D /backups/$NEWBASE -Fp -Xs -c fast -P -v && pg_verifybackup /backups/$NEWBASE"
echo "NEW BASE BACKUP $NEWBASE finished at $(utc)" | tee -a evidence/00_base_backup.txt
dpsql -c "SELECT archived_count, last_archived_wal, failed_count FROM pg_stat_archiver;"
```
Takes and verifies a fresh base backup on the new timeline. The old one can't take the server forward past the recovery point. The last query confirms archiving still works.

```bash
docker ps -a --filter name=drill; docker volume ls --filter name=drill
```
Shows that `drill_damaged` and `drill_data` are still there, alongside the recovered server.

## Step 9. Push (no data directories or WAL files)

```bash
cd ~/cit408-coralbay && mkdir -p week3/drill
cp -R ~/cit408-drill/evidence week3/drill/
cp ~/cit408-drill/verify_paused.txt ~/cit408-drill/verify_after.txt ~/cit408-drill/lost_batches.txt week3/drill/evidence/
```
Copies the evidence and outputs into the repository. Only text files and screenshots are committed, never backups or WAL.
