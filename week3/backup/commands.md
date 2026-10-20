# Assignment 3.1: Back up and restore Superstore, every command in order

**Server:** Supabase PostgreSQL, through the session pooler (`aws-0-us-east-1.pooler.supabase.com:5432`).
**Data:** the Superstore tables live in the **`superstore` schema of the `coralbay` database**, built in Assignment 2.3. Every dump therefore targets `-d coralbay -n superstore`.
**Restore target:** a new database, `superstore_restore`.
**Client:** macOS Terminal on my MacBook, with the PostgreSQL 17 client tools from Homebrew.
**Backup folder:** `~/cit408-backups/`, on my computer and outside the Git repository.

Every block below can be pasted into Terminal as is. Each command has a one-line explanation under it.

---

## Step 0. Set up the Mac (one time)

```bash
brew install postgresql@17
```
Installs `psql`, `pg_dump`, `pg_dumpall` and `pg_restore`. No local server is started.

```bash
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
```
Puts the PostgreSQL 17 tools first on the PATH for this Terminal window. On an Intel Mac, use `/usr/local/opt/postgresql@17/bin` instead.

```bash
pg_dump --version
```
Confirms the tools are found (expect `pg_dump (PostgreSQL) 17.x`).

```bash
export PGHOST=aws-0-us-east-1.pooler.supabase.com PGPORT=5432 PGSSLMODE=require
export REF=ddbnostktrlunbeojwwu
export DAY=$(date +%F)
```
Stores the Supabase connection details and today's date, so later commands stay short. The date goes into every file name.

```bash
mkdir -p ~/cit408-backups && cd ~/cit408-backups
```
Creates the backup folder on my computer and works from inside it.

```bash
psql -U postgres.$REF -d coralbay -c "SELECT version();"
```
Tests the connection as `postgres`. It asks for the same password pgAdmin uses.

> **Tip:** to avoid typing the password for every command, run `export PGPASSWORD='<postgres password>'` once. Run `unset PGPASSWORD` before Step 2, so the backups really run with backup_operator's own password.

---

## Step 1. Create the least-privilege backup role (as postgres)

```bash
psql -U postgres.$REF -d coralbay <<'SQL'
CREATE ROLE superstore_reader NOLOGIN;
GRANT CONNECT ON DATABASE coralbay TO superstore_reader;
GRANT USAGE ON SCHEMA superstore TO superstore_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA superstore TO superstore_reader;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA superstore TO superstore_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA superstore GRANT SELECT ON TABLES TO superstore_reader;
CREATE ROLE backup_operator LOGIN IN ROLE superstore_reader;
SQL
```
Here is what each line does:
- **CREATE ROLE superstore_reader NOLOGIN:** a group role that holds the read permissions. Nobody can log in as it.
- **GRANT CONNECT and GRANT USAGE:** members can connect to coralbay and see the superstore schema, but can't create anything in it.
- **GRANT SELECT ON ALL TABLES and SEQUENCES:** read-only access to all 11 tables and to the identity sequence behind `product_key`. INSERT, UPDATE, DELETE and TRUNCATE are not granted.
- **ALTER DEFAULT PRIVILEGES:** tables added later are readable too, so a new table can't silently drop out of the backups.
- **CREATE ROLE backup_operator ... IN ROLE superstore_reader:** the login role inherits read-only access and nothing else. It is not a superuser, can't create roles or databases, and can't write.

```bash
psql -U postgres.$REF -d coralbay -c "\password backup_operator"
```
Sets backup_operator's password. psql prompts for it twice and sends it encrypted.

```bash
psql -U postgres.$REF -d coralbay -c "\du backup_operator" -c "\du superstore_reader" -c "\drg backup_operator"
```
Shows the two roles' attributes and the membership. psql 16+ lists memberships under `\drg`, because the "Member of" column was removed from `\du`. **📸 Screenshot 2.**

```bash
psql -U backup_operator.$REF -d coralbay -c "SELECT count(*) FROM superstore.order_line;" \
                                         -c "DELETE FROM superstore.region;"
```
Least-privilege test, logged in as backup_operator. The read returns 9994, and the delete fails with `permission denied for table region`. The user name ends in `.$REF` because the Supabase pooler requires it.

---

## Step 2. Take the three backups (as backup_operator)

```bash
unset PGPASSWORD
```
Makes sure the next commands authenticate as backup_operator, with its own password.

```bash
/usr/bin/time -p pg_dump -U backup_operator.$REF -d coralbay -n superstore -Fc -f superstore_$DAY.dump
```
Writes a **custom-format** dump of the superstore schema. It is compressed, and pg_restore can restore one table from it at a time. `/usr/bin/time -p` prints how long it took (`real` = seconds).

```bash
/usr/bin/time -p pg_dump -U backup_operator.$REF -d coralbay -n superstore -Fp -f superstore_$DAY.sql
```
Writes a **plain SQL** dump of the same schema. It is readable in any editor and can be replayed with psql, even without pg_restore.

```bash
/usr/bin/time -p pg_dumpall -U backup_operator.$REF -l coralbay --roles-only --no-role-passwords -f roles_$DAY.sql
```
Dumps the server's **roles** and their memberships. Passwords are left out, because a read-only role can't read them and they shouldn't be in a backup file anyway.

```bash
ls -lh ~/cit408-backups
```
Lists the three files and their sizes. pg_dump ran on my Mac and pulled the data over the network, so the files were written straight to my computer and are already off the server. **📸 Screenshot 4:** open the folder with `open ~/cit408-backups`, switch Finder to List view (⌘2), and show the Size column.

---

## Step 3. Full restore into a new database (as postgres)

```bash
export PGPASSWORD='<postgres password>'
```
Switches back to the postgres account, which needs to create a database and own the restored objects.

```bash
psql -U postgres.$REF -d postgres -c "CREATE DATABASE superstore_restore;"
```
Creates an empty database to restore into. The original in coralbay stays untouched.

```bash
/usr/bin/time -p pg_restore -U postgres.$REF -d superstore_restore --no-owner superstore_$DAY.dump
```
Restores the whole custom dump: the schema, all 11 tables, data, keys, constraints, indexes and grants. `--no-owner` makes postgres own everything. The `real` time is the full-restore measurement.

```bash
psql -U postgres.$REF -d coralbay           -f verify.sql | tee verify_original.txt
psql -U postgres.$REF -d superstore_restore -f verify.sql | tee verify_restore.txt
```
Runs the same checks on both databases and saves the output. Every row count, total sales and total profit must match to the cent.

---

## Step 4. Single-table rescue (superstore_restore only)

```bash
pg_restore -l superstore_$DAY.dump | grep order_line
```
Lists the dump's contents for order_line. It shows a separate `TABLE DATA superstore order_line` entry, which can be restored on its own.

```bash
psql -U postgres.$REF -d superstore_restore -c "DELETE FROM superstore.order_line;" \
                                           -c "SELECT count(*) FROM superstore.order_line;"
```
Simulates the accident by deleting all 9,994 order lines in the restored copy only. The count confirms 0.

```bash
/usr/bin/time -p pg_restore -U postgres.$REF -d superstore_restore --data-only -n superstore -t order_line superstore_$DAY.dump
```
Restores only order_line's rows. `--data-only` leaves the table definition alone, and `-n` with `-t` limits the restore to that single table. No other table is read or written, and the foreign keys hold because orders and product were never emptied.

```bash
psql -U postgres.$REF -d superstore_restore -f verify.sql | tee verify_rescue.txt
```
Proves the rescue. Counts and totals match the original again. In the V3 output, only order_line shows deletes and a second load. Every other table was loaded once and never touched.

---

## Step 5. Push to GitHub (backup files stay out)

```bash
cd ~/cit408-coralbay
mkdir -p week3/backup
grep -qxF '*.dump' .gitignore || echo '*.dump' >> .gitignore
```
Creates the submission folder and makes Git ignore dump files. The backups also live outside the repo, in `~/cit408-backups/`.

```bash
git add .gitignore week3/backup/commands.md && git commit -m "Week 3: backup and restore commands"
git add week3/backup/verify.sql && git commit -m "Week 3: restore verification with output"
git add week3/backup/backup_plan.md && git commit -m "Week 3: backup plan with RPO and RTO"
git add week3/backup/*.png && git commit -m "Week 3: shift report, roles and backup folder screenshots"
git push
```
Commits one step at a time and pushes. `git status` must not list any `.dump` file or backup `.sql` file.
