-- verify.sql
-- CIT 408 · Assignment 3.1 · Proof that the backup restores completely.
-- The same three queries run against the original (coralbay, schema superstore) and the restored copy
-- (superstore_restore). Every row count, total sales and total profit must match to the cent.
--
-- Run:  psql -U postgres.<ref> -d coralbay           -f verify.sql
--       psql -U postgres.<ref> -d superstore_restore -f verify.sql
-- The captured output of each run is pasted at the end of this file.
-- Run on 2026-10-20 against Supabase PostgreSQL 17.6, from my Mac (psql 17.11).
-- Measured: custom dump 15.03 s (865 KB) · plain dump 14.22 s (3.2 MB) · roles dump 11.13 s (7.9 KB)
--           full restore 9.59 s · single-table rescue 2.64 s
-- Note: in coralbay, V3 reports 9,995 inserts on order_line. The extra one is the rejected insert
-- from Assignment 2.3's foreign key test; PostgreSQL counts the attempt. The table holds 9,994 rows (V1).

-- V1. Row count of every table in the superstore schema
SELECT current_database() AS db, t.table_name, t.row_count
FROM (
          SELECT 'superstore_staging' AS table_name, count(*) AS row_count FROM superstore.superstore_staging
UNION ALL SELECT 'region',        count(*) FROM superstore.region
UNION ALL SELECT 'state',         count(*) FROM superstore.state
UNION ALL SELECT 'postal_area',   count(*) FROM superstore.postal_area
UNION ALL SELECT 'ship_location', count(*) FROM superstore.ship_location
UNION ALL SELECT 'customer',      count(*) FROM superstore.customer
UNION ALL SELECT 'category',      count(*) FROM superstore.category
UNION ALL SELECT 'sub_category',  count(*) FROM superstore.sub_category
UNION ALL SELECT 'product',       count(*) FROM superstore.product
UNION ALL SELECT 'orders',        count(*) FROM superstore.orders
UNION ALL SELECT 'order_line',    count(*) FROM superstore.order_line
) t
ORDER BY t.table_name;

-- V2. Total sales and total profit, to the cent and exact
SELECT current_database()    AS db,
       count(*)              AS order_lines,
       round(sum(sales), 2)  AS total_sales,
       round(sum(profit), 2) AS total_profit,
       sum(sales)            AS exact_sales,
       sum(profit)           AS exact_profit
FROM superstore.order_line;

-- V3. Write activity per table since the database was created
--     (in superstore_restore after the rescue, only order_line shows deletes and a second load)
SELECT current_database() AS db, relname AS table_name, n_tup_ins AS rows_inserted, n_tup_del AS rows_deleted
FROM pg_stat_user_tables
WHERE schemaname = 'superstore'
ORDER BY relname;

-- =====================================================================================
-- OUTPUT 1: ORIGINAL database (coralbay), before any restore
-- =====================================================================================
--     db    |     table_name     | row_count 
-- ----------+--------------------+-----------
--  coralbay | category           |         3
--  coralbay | customer           |       793
--  coralbay | order_line         |      9994
--  coralbay | orders             |      5009
--  coralbay | postal_area        |       631
--  coralbay | product            |      1894
--  coralbay | region             |         4
--  coralbay | ship_location      |       632
--  coralbay | state              |        49
--  coralbay | sub_category       |        17
--  coralbay | superstore_staging |      9994
-- (11 rows)
--
--     db    | order_lines | total_sales | total_profit | exact_sales  | exact_profit 
-- ----------+-------------+-------------+--------------+--------------+--------------
--  coralbay |        9994 |  2297200.86 |    286397.02 | 2297200.8603 |  286397.0217
-- (1 row)

-- =====================================================================================
-- OUTPUT 2: FULL RESTORE (superstore_restore), straight after pg_restore of the custom dump
-- Result: all 11 row counts match OUTPUT 1, and total sales 2,297,200.86 / profit 286,397.02 match to the cent.
-- =====================================================================================
--          db         |     table_name     | row_count 
-- --------------------+--------------------+-----------
--  superstore_restore | category           |         3
--  superstore_restore | customer           |       793
--  superstore_restore | order_line         |      9994
--  superstore_restore | orders             |      5009
--  superstore_restore | postal_area        |       631
--  superstore_restore | product            |      1894
--  superstore_restore | region             |         4
--  superstore_restore | ship_location      |       632
--  superstore_restore | state              |        49
--  superstore_restore | sub_category       |        17
--  superstore_restore | superstore_staging |      9994
-- (11 rows)
--
--          db         | order_lines | total_sales | total_profit | exact_sales  | exact_profit 
-- --------------------+-------------+-------------+--------------+--------------+--------------
--  superstore_restore |        9994 |  2297200.86 |    286397.02 | 2297200.8603 |  286397.0217
-- (1 row)

-- =====================================================================================
-- SINGLE-TABLE RESCUE (superstore_restore only)
--   DELETE FROM superstore.order_line;
--   SELECT count(*) FROM superstore.order_line;   -->  0
--   pg_restore --data-only -n superstore -t order_line superstore_<date>.dump
-- =====================================================================================

-- OUTPUT 3: after the rescue. Counts and totals match OUTPUT 1 again.
-- V3 proves no other table was touched: only order_line shows deletes (9,994) and a second
-- load (19,988 = 9,994 from the full restore + 9,994 from the rescue). Every other table was
-- inserted exactly once, by the full restore, and never deleted from.
--          db         |     table_name     | row_count 
-- --------------------+--------------------+-----------
--  superstore_restore | category           |         3
--  superstore_restore | customer           |       793
--  superstore_restore | order_line         |      9994
--  superstore_restore | orders             |      5009
--  superstore_restore | postal_area        |       631
--  superstore_restore | product            |      1894
--  superstore_restore | region             |         4
--  superstore_restore | ship_location      |       632
--  superstore_restore | state              |        49
--  superstore_restore | sub_category       |        17
--  superstore_restore | superstore_staging |      9994
-- (11 rows)
--
--          db         | order_lines | total_sales | total_profit | exact_sales  | exact_profit 
-- --------------------+-------------+-------------+--------------+--------------+--------------
--  superstore_restore |        9994 |  2297200.86 |    286397.02 | 2297200.8603 |  286397.0217
-- (1 row)
--
--          db         |     table_name     | rows_inserted | rows_deleted 
-- --------------------+--------------------+---------------+--------------
--  superstore_restore | category           |             3 |            0
--  superstore_restore | customer           |           793 |            0
--  superstore_restore | order_line         |         19988 |         9994
--  superstore_restore | orders             |          5009 |            0
--  superstore_restore | postal_area        |           631 |            0
--  superstore_restore | product            |          1894 |            0
--  superstore_restore | region             |             4 |            0
--  superstore_restore | ship_location      |           632 |            0
--  superstore_restore | state              |            49 |            0
--  superstore_restore | sub_category       |            17 |            0
--  superstore_restore | superstore_staging |          9994 |            0
-- (11 rows)
