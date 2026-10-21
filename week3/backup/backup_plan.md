# Superstore backup plan

**Database:** `superstore` schema in the `coralbay` database (Supabase PostgreSQL), with 11 tables and 9,994 order lines
**Owner:** Waqar Javed · **Backup role:** `backup_operator` (read-only, member of `superstore_reader`)
**Plan date:** 2026-10-20

## 1. Measured on 2026-10-20

| Step | Time | File | Size |
|---|---|---|---|
| Custom-format dump (`pg_dump -Fc`) | 15.03 s | `superstore_2026-10-20.dump` | 865 KB |
| Plain SQL dump (`pg_dump -Fp`) | 14.22 s | `superstore_2026-10-20.sql` | 3.2 MB |
| Roles dump (`pg_dumpall --roles-only`) | 11.13 s | `roles_2026-10-20.sql` | 7.9 KB |
| Full restore (`pg_restore` into `superstore_restore`) | 9.59 s | | |
| Single-table rescue (`order_line`, data only) | 2.64 s | | |

Times are the `real` value printed by `/usr/bin/time -p`, measured from my Mac over the internet to Supabase. The three dump times include the few seconds I spent typing backup_operator's password at the prompt, so the dumps themselves are faster than shown. The restore times ran with no prompt and are pure work. The custom dump is about a quarter the size of the plain dump (865 KB against 3.2 MB) because it is compressed. Sizes are from `ls -lh`, which counts 1 KB as 1,024 bytes; Finder counts 1 KB as 1,000 bytes, so it shows the same files as 886 KB, 3.3 MB and 8 KB.

## 2. When Superstore is backed up

| Backup | Schedule | Command |
|---|---|---|
| Custom-format dump | **Every night at 02:00**, plus by hand before any schema change or bulk load | `pg_dump -Fc -n superstore` as `backup_operator` |
| Plain SQL dump | Every Sunday at 02:00 | `pg_dump -Fp -n superstore` |
| Roles dump | Every Sunday, and after any role or grant change | `pg_dumpall --roles-only --no-role-passwords` |

I chose a nightly schedule because a dump takes only seconds and puts almost no load on the server. 02:00 is outside business hours, so the dump does not compete with order entry. The plain dump is weekly because it is a readable fallback for when pg_restore is unavailable, not the main restore path.

## 3. How long backups are kept

| Tier | Kept | Count on hand |
|---|---|---|
| Daily custom dumps | 14 days | 14 |
| Weekly (Sunday) custom + plain + roles | 8 weeks | 8 sets |
| Monthly (first Sunday) | 12 months | 12 sets |

Old files are deleted only after the newest backup of the same tier has passed its restore test. At current sizes, the whole retention set is well under 100 MB.

## 4. Where the copies live (3-2-1)

1. **On the server:** Supabase's own daily platform backup. It is managed by Supabase, and I do not control its schedule or retention.
2. **On my computer:** `~/cit408-backups/`, where pg_dump writes each file directly over the network, so it is off the server from the moment it is written. This folder is outside the Git repository, and `.gitignore` blocks `*.dump`.
3. **Off-site:** a copy synced to cloud storage (Google Drive), so losing my laptop does not lose the backups.

That gives three copies on two kinds of storage, with one off-site. The roles dump contains no passwords, so a leaked file does not expose credentials.

## 5. How often a restore is tested

- **Weekly (Sunday):** restore the newest custom dump into `superstore_restore` and run `verify.sql`. All 11 row counts, total sales and total profit must match the source to the cent. A restore that prints no errors is not counted as a pass until those numbers match.
- **Monthly:** also run the single-table rescue drill: delete `order_line` in the restored copy, restore that table alone from the dump, and re-verify.
- Each test records the date, the file used, the restore time and pass or fail. A failed test is fixed before the next nightly dump is trusted.

## 6. RPO and RTO

**RPO (recovery point objective): 24 hours.** With one dump per night, the worst case is a failure just before the next dump, which loses up to a day of changes. Taking a manual dump before every bulk load or schema change narrows that window when risk is highest. To get below 24 hours, the next step would be dumps every few hours (still cheap at about 15 s each) or point-in-time recovery from WAL archiving.

**RTO (recovery time objective): 1 hour.** The measured work is small: a full restore took 9.59 s and verification takes about a minute. The hour covers what a real incident adds on top:

| Activity | Time allowed |
|---|---|
| Detect the failure and decide to restore | 20 min |
| Find and download the newest good dump | 10 min |
| Create the target database and run `pg_restore` (measured 9.59 s) | 10 min |
| Run `verify.sql` and compare counts and totals | 10 min |
| Point the application at the restored database | 10 min |

A one-table accident, such as rows deleted from `order_line`, is faster to fix: the single-table rescue took 2.64 s and touches nothing else. Its RTO is about 15 minutes.
