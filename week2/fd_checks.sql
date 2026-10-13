-- fd_checks.sql
-- CIT 408 · Assignment 2.1 · Coral Bay fleet work orders
-- Proof queries for every functional dependency listed in dependencies.md.
-- Pattern: GROUP BY the determinant, HAVING count(DISTINCT dependent) > 1.
-- Zero rows returned = the dependency holds for all 2,258 part lines.
-- Checks run against the 1NF view below, so a determinant that repeats across
-- part lines (e.g. work_order_no) is actually tested, not trivially unique.
-- Staging table name: work_orders_unf (rename if your load script used another name).
--
-- HOW TO RUN IN pgADMIN (Query Tool connected to the coralbay database)
--   Whole file : press F5 with nothing selected. Everything runs top to bottom and the
--                Data Output panel shows the SUMMARY table (last query) with all checks.
--   One check  : highlight a single query (SELECT ... ;) and press F5 to see its own result.
--                Run STEP 0 (CREATE OR REPLACE VIEW wo_1nf) first in a new session.
--   The "-- Result:" blocks are the captured output; comments are ignored when running.

-- ============================================================
-- STEP 0. 1NF view: one row per (work order, part used)
-- ============================================================
CREATE OR REPLACE VIEW wo_1nf AS
SELECT w.work_order_no, w.open_date, w.close_date,
       w.truck_id, w.truck_vin, w.truck_make, w.truck_model, w.truck_year,
       w.depot_code, w.depot_name, w.depot_city, w.depot_phone,
       w.mechanic_id, w.mechanic_name, w.mechanic_cert_level, w.cert_hourly_rate,
       w.labor_hours, w.problem_description,
       p.part_slot, p.part_code, p.part_name, p.part_unit_cost, p.part_qty,
       p.supplier_id, p.supplier_name, p.supplier_phone
FROM work_orders_unf w
CROSS JOIN LATERAL (VALUES
  (1, w.part1_code, w.part1_name, w.part1_unit_cost, w.part1_qty, w.part1_supplier_id, w.part1_supplier_name, w.part1_supplier_phone),
  (2, w.part2_code, w.part2_name, w.part2_unit_cost, w.part2_qty, w.part2_supplier_id, w.part2_supplier_name, w.part2_supplier_phone),
  (3, w.part3_code, w.part3_name, w.part3_unit_cost, w.part3_qty, w.part3_supplier_id, w.part3_supplier_name, w.part3_supplier_phone),
  (4, w.part4_code, w.part4_name, w.part4_unit_cost, w.part4_qty, w.part4_supplier_id, w.part4_supplier_name, w.part4_supplier_phone)
) AS p(part_slot, part_code, part_name, part_unit_cost, part_qty, supplier_id, supplier_name, supplier_phone)
WHERE p.part_code IS NOT NULL;

-- Result:
-- CREATE VIEW

-- 0a. Row count of the 1NF view (= total filled part slots)
SELECT count(*) AS part_lines FROM wo_1nf;

-- Result:
--  part_lines 
-- ------------
--        2258
-- (1 row)

-- 0b. Primary key proof: (work_order_no, part_code) is never NULL and never repeats
SELECT count(*)                                    AS part_lines,
       count(DISTINCT (work_order_no, part_code))  AS distinct_keys,
       count(*) FILTER (WHERE work_order_no IS NULL OR part_code IS NULL) AS null_keys
FROM wo_1nf;

-- Result:
--  part_lines | distinct_keys | null_keys 
-- ------------+---------------+-----------
--        2258 |          2258 |         0
-- (1 row)

-- 0c. Primary key proof, duplicate form: no key value occurs twice
SELECT work_order_no, part_code, count(*)
FROM wo_1nf
GROUP BY work_order_no, part_code
HAVING count(*) > 1;

-- Result:
--  work_order_no | part_code | count 
-- ---------------+-----------+-------
-- (0 rows)

-- 0d. Neither half of the key is enough on its own (so the key is minimal)
SELECT (SELECT count(*) FROM (SELECT work_order_no FROM wo_1nf GROUP BY 1 HAVING count(*) > 1) a) AS work_orders_on_many_lines,
       (SELECT count(*) FROM (SELECT part_code     FROM wo_1nf GROUP BY 1 HAVING count(*) > 1) b) AS parts_on_many_lines;

-- Result:
--  work_orders_on_many_lines | parts_on_many_lines 
-- ---------------------------+---------------------
--                        714 |                  24
-- (1 row)

-- ============================================================
-- FULL DEPENDENCY
-- ============================================================
-- FD1. (work_order_no, part_code) -> part_qty                       [FULL]
SELECT work_order_no, part_code,
       count(DISTINCT part_qty) AS n_part_qty
FROM wo_1nf
GROUP BY work_order_no, part_code
HAVING count(DISTINCT part_qty) > 1;

-- Result:
--  work_order_no | part_code | n_part_qty 
-- ---------------+-----------+------------
-- (0 rows)

-- FD1 support: neither key column alone determines part_qty (rows returned = not determined)
SELECT (SELECT count(*) FROM (SELECT work_order_no FROM wo_1nf GROUP BY 1 HAVING count(DISTINCT part_qty) > 1) a) AS wo_alone_fails,
       (SELECT count(*) FROM (SELECT part_code     FROM wo_1nf GROUP BY 1 HAVING count(DISTINCT part_qty) > 1) b) AS part_alone_fails;

-- Result:
--  wo_alone_fails | part_alone_fails 
-- ----------------+------------------
--             602 |               24
-- (1 row)

-- ============================================================
-- PARTIAL DEPENDENCIES (depend on one column of the composite key)
-- ============================================================
-- FD2. work_order_no -> open_date, close_date, truck_id, depot_code, mechanic_id, labor_hours, problem_description   [PARTIAL]
SELECT work_order_no,
       count(DISTINCT open_date) AS n_open_date,
       count(DISTINCT close_date) AS n_close_date,
       count(DISTINCT truck_id) AS n_truck_id,
       count(DISTINCT depot_code) AS n_depot_code,
       count(DISTINCT mechanic_id) AS n_mechanic_id,
       count(DISTINCT labor_hours) AS n_labor_hours,
       count(DISTINCT problem_description) AS n_problem_description
FROM wo_1nf
GROUP BY work_order_no
HAVING count(DISTINCT open_date) > 1
    OR count(DISTINCT close_date) > 1
    OR count(DISTINCT truck_id) > 1
    OR count(DISTINCT depot_code) > 1
    OR count(DISTINCT mechanic_id) > 1
    OR count(DISTINCT labor_hours) > 1
    OR count(DISTINCT problem_description) > 1;

-- Result:
--  work_order_no | n_open_date | n_close_date | n_truck_id | n_depot_code | n_mechanic_id | n_labor_hours | n_problem_description 
-- ---------------+-------------+--------------+------------+--------------+---------------+---------------+-----------------------
-- (0 rows)

-- FD3. part_code -> part_name, part_unit_cost, supplier_id         [PARTIAL]
SELECT part_code,
       count(DISTINCT part_name) AS n_part_name,
       count(DISTINCT part_unit_cost) AS n_part_unit_cost,
       count(DISTINCT supplier_id) AS n_supplier_id
FROM wo_1nf
GROUP BY part_code
HAVING count(DISTINCT part_name) > 1
    OR count(DISTINCT part_unit_cost) > 1
    OR count(DISTINCT supplier_id) > 1;

-- Result:
--  part_code | n_part_name | n_part_unit_cost | n_supplier_id 
-- -----------+-------------+------------------+---------------
-- (0 rows)

-- ============================================================
-- TRANSITIVE DEPENDENCIES (non-key column -> non-key column)
-- ============================================================
-- FD4. truck_id -> truck_vin, truck_model, truck_year              [TRANSITIVE: work_order_no -> truck_id -> ...]
SELECT truck_id,
       count(DISTINCT truck_vin) AS n_truck_vin,
       count(DISTINCT truck_model) AS n_truck_model,
       count(DISTINCT truck_year) AS n_truck_year
FROM wo_1nf
GROUP BY truck_id
HAVING count(DISTINCT truck_vin) > 1
    OR count(DISTINCT truck_model) > 1
    OR count(DISTINCT truck_year) > 1;

-- Result:
--  truck_id | n_truck_vin | n_truck_model | n_truck_year 
-- ----------+-------------+---------------+--------------
-- (0 rows)

-- FD5. truck_model -> truck_make                                   [TRANSITIVE, 2nd hop: truck_id -> truck_model -> truck_make]
SELECT truck_model,
       count(DISTINCT truck_make) AS n_truck_make
FROM wo_1nf
GROUP BY truck_model
HAVING count(DISTINCT truck_make) > 1;

-- Result:
--  truck_model | n_truck_make 
-- -------------+--------------
-- (0 rows)

-- FD6. depot_code -> depot_name, depot_city, depot_phone           [TRANSITIVE: work_order_no -> depot_code -> ...]
-- EXPECTED TO FAIL: this is the one conflicting value in the file (see CONFLICT section below).
SELECT depot_code,
       count(DISTINCT depot_name) AS n_depot_name,
       count(DISTINCT depot_city) AS n_depot_city,
       count(DISTINCT depot_phone) AS n_depot_phone
FROM wo_1nf
GROUP BY depot_code
HAVING count(DISTINCT depot_name) > 1
    OR count(DISTINCT depot_city) > 1
    OR count(DISTINCT depot_phone) > 1;

-- Result:
--  depot_code | n_depot_name | n_depot_city | n_depot_phone 
-- ------------+--------------+--------------+---------------
--  DEP-FLL    |            1 |            1 |             2
-- (1 row)

-- FD7. mechanic_id -> mechanic_name, mechanic_cert_level           [TRANSITIVE: work_order_no -> mechanic_id -> ...]
SELECT mechanic_id,
       count(DISTINCT mechanic_name) AS n_mechanic_name,
       count(DISTINCT mechanic_cert_level) AS n_mechanic_cert_level
FROM wo_1nf
GROUP BY mechanic_id
HAVING count(DISTINCT mechanic_name) > 1
    OR count(DISTINCT mechanic_cert_level) > 1;

-- Result:
--  mechanic_id | n_mechanic_name | n_mechanic_cert_level 
-- -------------+-----------------+-----------------------
-- (0 rows)

-- FD8. mechanic_cert_level -> cert_hourly_rate                     [TRANSITIVE, 2nd hop: mechanic_id -> mechanic_cert_level -> cert_hourly_rate]
SELECT mechanic_cert_level,
       count(DISTINCT cert_hourly_rate) AS n_cert_hourly_rate
FROM wo_1nf
GROUP BY mechanic_cert_level
HAVING count(DISTINCT cert_hourly_rate) > 1;

-- Result:
--  mechanic_cert_level | n_cert_hourly_rate 
-- ---------------------+--------------------
-- (0 rows)

-- FD8 support: mechanic_id -> cert_hourly_rate also holds, but only BECAUSE of FD7 + FD8
SELECT mechanic_id,
       count(DISTINCT cert_hourly_rate) AS n_cert_hourly_rate
FROM wo_1nf
GROUP BY mechanic_id
HAVING count(DISTINCT cert_hourly_rate) > 1;

-- Result:
--  mechanic_id | n_cert_hourly_rate 
-- -------------+--------------------
-- (0 rows)

-- FD9. supplier_id -> supplier_name, supplier_phone                [TRANSITIVE: part_code -> supplier_id -> ...]
SELECT supplier_id,
       count(DISTINCT supplier_name) AS n_supplier_name,
       count(DISTINCT supplier_phone) AS n_supplier_phone
FROM wo_1nf
GROUP BY supplier_id
HAVING count(DISTINCT supplier_name) > 1
    OR count(DISTINCT supplier_phone) > 1;

-- Result:
--  supplier_id | n_supplier_name | n_supplier_phone 
-- -------------+-----------------+------------------
-- (0 rows)

-- ============================================================
-- ALTERNATE-KEY DEPENDENCIES (enforced as UNIQUE in 3NF)
-- ============================================================
-- FD10. truck_vin -> truck_id                                      [TRANSITIVE; VIN is a candidate key of TRUCK]
SELECT truck_vin,
       count(DISTINCT truck_id) AS n_truck_id
FROM wo_1nf
GROUP BY truck_vin
HAVING count(DISTINCT truck_id) > 1;

-- Result:
--  truck_vin | n_truck_id 
-- -----------+------------
-- (0 rows)

-- FD11. depot_name -> depot_code                                   [TRANSITIVE; candidate key of DEPOT]
SELECT depot_name,
       count(DISTINCT depot_code) AS n_depot_code
FROM wo_1nf
GROUP BY depot_name
HAVING count(DISTINCT depot_code) > 1;

-- Result:
--  depot_name | n_depot_code 
-- ------------+--------------
-- (0 rows)

-- FD12. part_name -> part_code                                     [non-key -> key column; candidate key of PART]
SELECT part_name,
       count(DISTINCT part_code) AS n_part_code
FROM wo_1nf
GROUP BY part_name
HAVING count(DISTINCT part_code) > 1;

-- Result:
--  part_name | n_part_code 
-- -----------+-------------
-- (0 rows)

-- FD13. supplier_name -> supplier_id                               [TRANSITIVE; candidate key of SUPPLIER]
SELECT supplier_name,
       count(DISTINCT supplier_id) AS n_supplier_id
FROM wo_1nf
GROUP BY supplier_name
HAVING count(DISTINCT supplier_id) > 1;

-- Result:
--  supplier_name | n_supplier_id 
-- ---------------+---------------
-- (0 rows)

-- FD14. supplier_phone -> supplier_id                              [TRANSITIVE; candidate key of SUPPLIER]
SELECT supplier_phone,
       count(DISTINCT supplier_id) AS n_supplier_id
FROM wo_1nf
GROUP BY supplier_phone
HAVING count(DISTINCT supplier_id) > 1;

-- Result:
--  supplier_phone | n_supplier_id 
-- ----------------+---------------
-- (0 rows)

-- ============================================================
-- HOLD IN THIS SAMPLE BUT REJECTED ON BUSINESS MEANING (not enforced)
-- ============================================================
-- R1. truck_make -> truck_model  (holds only because the fleet buys one model per make)
SELECT truck_make,
       count(DISTINCT truck_model) AS n_truck_model
FROM wo_1nf
GROUP BY truck_make
HAVING count(DISTINCT truck_model) > 1;

-- Result:
--  truck_make | n_truck_model 
-- ------------+---------------
-- (0 rows)

-- R2. cert_hourly_rate -> mechanic_cert_level  (two levels could share a rate in future)
SELECT cert_hourly_rate,
       count(DISTINCT mechanic_cert_level) AS n_mechanic_cert_level
FROM wo_1nf
GROUP BY cert_hourly_rate
HAVING count(DISTINCT mechanic_cert_level) > 1;

-- Result:
--  cert_hourly_rate | n_mechanic_cert_level 
-- ------------------+-----------------------
-- (0 rows)

-- R3. mechanic_name -> mechanic_id  (two people can share a name)
SELECT mechanic_name,
       count(DISTINCT mechanic_id) AS n_mechanic_id
FROM wo_1nf
GROUP BY mechanic_name
HAVING count(DISTINCT mechanic_id) > 1;

-- Result:
--  mechanic_name | n_mechanic_id 
-- ---------------+---------------
-- (0 rows)

-- R4. depot_city -> depot_code  (a second depot could open in the same city)
SELECT depot_city,
       count(DISTINCT depot_code) AS n_depot_code
FROM wo_1nf
GROUP BY depot_city
HAVING count(DISTINCT depot_code) > 1;

-- Result:
--  depot_city | n_depot_code 
-- ------------+--------------
-- (0 rows)

-- ============================================================
-- CANDIDATES THAT DO NOT HOLD (rows returned = not a dependency)
-- ============================================================
-- N1. mechanic_id -> depot_code  (mechanics work at more than one depot)
SELECT count(*) AS mechanics_at_many_depots
FROM (SELECT mechanic_id FROM wo_1nf GROUP BY 1 HAVING count(DISTINCT depot_code) > 1) t;

-- Result:
--  mechanics_at_many_depots 
-- --------------------------
--                        18
-- (1 row)

-- N2. truck_id -> depot_code  (trucks are serviced at more than one depot)
SELECT count(*) AS trucks_at_many_depots
FROM (SELECT truck_id FROM wo_1nf GROUP BY 1 HAVING count(DISTINCT depot_code) > 1) t;

-- Result:
--  trucks_at_many_depots 
-- -----------------------
--                     40
-- (1 row)

-- N3. problem_description -> labor_hours  (same problem, different hours)
SELECT count(*) AS problems_with_many_hour_values
FROM (SELECT problem_description FROM wo_1nf GROUP BY 1 HAVING count(DISTINCT labor_hours) > 1) t;

-- Result:
--  problems_with_many_hour_values 
-- --------------------------------
--                              12
-- (1 row)

-- ============================================================
-- CONFLICT: the one value that breaks FD6
-- ============================================================
-- C1. Every phone recorded for each depot, with how many work orders use it
SELECT depot_code, depot_phone, count(*) AS work_orders
FROM work_orders_unf
GROUP BY depot_code, depot_phone
ORDER BY depot_code, work_orders DESC;

-- Result:
--  depot_code |  depot_phone   | work_orders 
-- ------------+----------------+-------------
--  DEP-DOR    | (305) 555-0162 |         275
--  DEP-FLL    | (954) 555-0118 |         266
--  DEP-FLL    | (954) 555-0181 |           2
--  DEP-MIA    | (305) 555-0140 |         299
--  DEP-TPA    | (813) 555-0175 |         258
-- (5 rows)

-- C2. The affected work orders
SELECT work_order_no, open_date, depot_code, depot_name, depot_phone, mechanic_id
FROM work_orders_unf
WHERE depot_code = 'DEP-FLL' AND depot_phone = '(954) 555-0181'
ORDER BY work_order_no;

-- Result:
--  work_order_no | open_date  | depot_code |      depot_name      |  depot_phone   | mechanic_id 
-- ---------------+------------+------------+----------------------+----------------+-------------
--  WO-50041      | 2026-01-13 | DEP-FLL    | Fort Lauderdale Yard | (954) 555-0181 | M01
--  WO-50047      | 2026-01-14 | DEP-FLL    | Fort Lauderdale Yard | (954) 555-0181 | M08
-- (2 rows)

-- C3. Resolution rule: majority value per depot_code (ties would be flagged for review).
--     Shows the value each depot will carry into the 3NF DEPOT table.
SELECT DISTINCT ON (depot_code) depot_code, depot_phone AS resolved_phone, count(*) AS supporting_rows
FROM work_orders_unf
GROUP BY depot_code, depot_phone
ORDER BY depot_code, count(*) DESC;

-- Result:
--  depot_code | resolved_phone | supporting_rows 
-- ------------+----------------+-----------------
--  DEP-DOR    | (305) 555-0162 |             275
--  DEP-FLL    | (954) 555-0118 |             266
--  DEP-MIA    | (305) 555-0140 |             299
--  DEP-TPA    | (813) 555-0175 |             258
-- (4 rows)

-- C4. FD6 re-checked after applying the rule (should now return 0 rows)
WITH resolved AS (
  SELECT DISTINCT ON (depot_code) depot_code, depot_phone
  FROM work_orders_unf
  GROUP BY depot_code, depot_phone
  ORDER BY depot_code, count(*) DESC)
SELECT w.depot_code, count(DISTINCT r.depot_phone) AS n_phone
FROM wo_1nf w JOIN resolved r USING (depot_code)
GROUP BY w.depot_code
HAVING count(DISTINCT r.depot_phone) > 1;

-- Result:
--  depot_code | n_phone 
-- ------------+---------
-- (0 rows)

-- ============================================================
-- SUMMARY (last query in the file)
-- In pgAdmin, pressing F5 on the whole file shows only this final result:
-- one row per dependency. Only FD6 should show a conflict.
-- ============================================================
SELECT dependency, label, violating_groups,
       CASE WHEN violating_groups = 0 THEN 'HOLDS' ELSE 'CONFLICT - see C1-C4' END AS status
FROM (
SELECT 0 AS ord, 'PK  (work_order_no, part_code) unique' AS dependency, 'key' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY work_order_no, part_code HAVING count(*) > 1) v) AS violating_groups
UNION ALL
SELECT 1 AS ord, 'FD1  (work_order_no, part_code) -> part_qty' AS dependency, 'Full' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY work_order_no, part_code HAVING count(DISTINCT part_qty) > 1) v) AS violating_groups
UNION ALL
SELECT 2 AS ord, 'FD2  work_order_no -> header columns' AS dependency, 'Partial' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY work_order_no HAVING count(DISTINCT open_date) > 1 OR count(DISTINCT close_date) > 1 OR count(DISTINCT truck_id) > 1 OR count(DISTINCT depot_code) > 1 OR count(DISTINCT mechanic_id) > 1 OR count(DISTINCT labor_hours) > 1 OR count(DISTINCT problem_description) > 1) v) AS violating_groups
UNION ALL
SELECT 3 AS ord, 'FD3  part_code -> part_name, unit_cost, supplier_id' AS dependency, 'Partial' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY part_code HAVING count(DISTINCT part_name) > 1 OR count(DISTINCT part_unit_cost) > 1 OR count(DISTINCT supplier_id) > 1) v) AS violating_groups
UNION ALL
SELECT 4 AS ord, 'FD4  truck_id -> vin, model, year' AS dependency, 'Transitive' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY truck_id HAVING count(DISTINCT truck_vin) > 1 OR count(DISTINCT truck_model) > 1 OR count(DISTINCT truck_year) > 1) v) AS violating_groups
UNION ALL
SELECT 5 AS ord, 'FD5  truck_model -> truck_make' AS dependency, 'Transitive (2nd hop)' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY truck_model HAVING count(DISTINCT truck_make) > 1) v) AS violating_groups
UNION ALL
SELECT 6 AS ord, 'FD6  depot_code -> name, city, phone' AS dependency, 'Transitive' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY depot_code HAVING count(DISTINCT depot_name) > 1 OR count(DISTINCT depot_city) > 1 OR count(DISTINCT depot_phone) > 1) v) AS violating_groups
UNION ALL
SELECT 7 AS ord, 'FD7  mechanic_id -> name, cert_level' AS dependency, 'Transitive' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY mechanic_id HAVING count(DISTINCT mechanic_name) > 1 OR count(DISTINCT mechanic_cert_level) > 1) v) AS violating_groups
UNION ALL
SELECT 8 AS ord, 'FD8  cert_level -> hourly_rate' AS dependency, 'Transitive (2nd hop)' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY mechanic_cert_level HAVING count(DISTINCT cert_hourly_rate) > 1) v) AS violating_groups
UNION ALL
SELECT 9 AS ord, 'FD9  supplier_id -> name, phone' AS dependency, 'Transitive' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY supplier_id HAVING count(DISTINCT supplier_name) > 1 OR count(DISTINCT supplier_phone) > 1) v) AS violating_groups
UNION ALL
SELECT 10 AS ord, 'FD10 truck_vin -> truck_id' AS dependency, 'Alternate key' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY truck_vin HAVING count(DISTINCT truck_id) > 1) v) AS violating_groups
UNION ALL
SELECT 11 AS ord, 'FD11 depot_name -> depot_code' AS dependency, 'Alternate key' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY depot_name HAVING count(DISTINCT depot_code) > 1) v) AS violating_groups
UNION ALL
SELECT 12 AS ord, 'FD12 part_name -> part_code' AS dependency, 'Alternate key' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY part_name HAVING count(DISTINCT part_code) > 1) v) AS violating_groups
UNION ALL
SELECT 13 AS ord, 'FD13 supplier_name -> supplier_id' AS dependency, 'Alternate key' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY supplier_name HAVING count(DISTINCT supplier_id) > 1) v) AS violating_groups
UNION ALL
SELECT 14 AS ord, 'FD14 supplier_phone -> supplier_id' AS dependency, 'Alternate key' AS label,
       (SELECT count(*) FROM (SELECT 1 FROM wo_1nf GROUP BY supplier_phone HAVING count(DISTINCT supplier_id) > 1) v) AS violating_groups
) s
ORDER BY ord;

-- Result:
--                      dependency                      |        label         | violating_groups |        status        
-- -----------------------------------------------------+----------------------+------------------+----------------------
--  PK  (work_order_no, part_code) unique               | key                  |                0 | HOLDS
--  FD1  (work_order_no, part_code) -> part_qty         | Full                 |                0 | HOLDS
--  FD2  work_order_no -> header columns                | Partial              |                0 | HOLDS
--  FD3  part_code -> part_name, unit_cost, supplier_id | Partial              |                0 | HOLDS
--  FD4  truck_id -> vin, model, year                   | Transitive           |                0 | HOLDS
--  FD5  truck_model -> truck_make                      | Transitive (2nd hop) |                0 | HOLDS
--  FD6  depot_code -> name, city, phone                | Transitive           |                1 | CONFLICT - see C1-C4
--  FD7  mechanic_id -> name, cert_level                | Transitive           |                0 | HOLDS
--  FD8  cert_level -> hourly_rate                      | Transitive (2nd hop) |                0 | HOLDS
--  FD9  supplier_id -> name, phone                     | Transitive           |                0 | HOLDS
--  FD10 truck_vin -> truck_id                          | Alternate key        |                0 | HOLDS
--  FD11 depot_name -> depot_code                       | Alternate key        |                0 | HOLDS
--  FD12 part_name -> part_code                         | Alternate key        |                0 | HOLDS
--  FD13 supplier_name -> supplier_id                   | Alternate key        |                0 | HOLDS
--  FD14 supplier_phone -> supplier_id                  | Alternate key        |                0 | HOLDS
-- (15 rows)

