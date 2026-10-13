-- explore.sql
-- CIT 408 · Assignment 2.1 · Coral Bay fleet work orders
-- Exploration of the unnormalized staging table loaded by w2_assignment_load_work_orders.sql.
-- Staging table name used below: work_orders_unf (rename if your load script used another name).
-- Results were captured from PostgreSQL and pasted under each query.
--
-- HOW TO RUN IN pgADMIN (Query Tool connected to the coralbay database)
--   Highlight one query (SELECT ... ;) and press F5 (fn+F5 on a Mac). The result shows in
--   Data Output. Pressing F5 with nothing selected runs every query but shows only the last one.

-- Q1. Row count and confirmation that work_order_no is unique in the raw file
SELECT count(*)                      AS total_rows,
       count(DISTINCT work_order_no) AS distinct_work_orders
FROM work_orders_unf;

-- Result:
--  total_rows | distinct_work_orders 
-- ------------+----------------------
--        1100 |                 1100
-- (1 row)

-- Q2. Distinct counts for every entity that repeats on each row
SELECT count(DISTINCT truck_id)            AS trucks,
       count(DISTINCT truck_vin)           AS vins,
       count(DISTINCT truck_model)         AS models,
       count(DISTINCT truck_make)          AS makes,
       count(DISTINCT depot_code)          AS depots,
       count(DISTINCT depot_phone)         AS depot_phones,
       count(DISTINCT mechanic_id)         AS mechanics,
       count(DISTINCT mechanic_cert_level) AS cert_levels,
       count(DISTINCT problem_description) AS problems
FROM work_orders_unf;

-- Result:
--  trucks | vins | models | makes | depots | depot_phones | mechanics | cert_levels | problems 
-- --------+------+--------+-------+--------+--------------+-----------+-------------+----------
--      40 |   40 |      7 |     7 |      4 |            5 |        18 |           4 |       12
-- (1 row)

-- Q3. Sample rows (header columns plus the first part slot)
SELECT work_order_no, open_date, close_date, truck_id, truck_model, depot_code,
       mechanic_id, mechanic_cert_level, cert_hourly_rate, labor_hours,
       part1_code, part1_qty, part1_supplier_id
FROM work_orders_unf
ORDER BY work_order_no
LIMIT 5;

-- Result:
--  work_order_no | open_date  | close_date | truck_id | truck_model | depot_code | mechanic_id | mechanic_cert_level | cert_hourly_rate | labor_hours | part1_code | part1_qty | part1_supplier_id 
-- ---------------+------------+------------+----------+-------------+------------+-------------+---------------------+------------------+-------------+------------+-----------+-------------------
--  WO-50001      | 2026-01-03 | 2026-01-04 | TRK-216  | VNL 860     | DEP-DOR    | M02         | Master              |           110.00 |        6.00 | P-7702     |         2 | SUP-01
--  WO-50002      | 2026-01-03 | 2026-01-03 | TRK-228  | L6          | DEP-DOR    | M04         | Level 1             |            58.00 |        2.50 | P-4410     |         1 | SUP-02
--  WO-50003      | 2026-01-03 | 2026-01-03 | TRK-203  | 579         | DEP-MIA    | M10         | Level 3             |            89.00 |        5.00 | P-4430     |         4 | SUP-03
--  WO-50004      | 2026-01-03 | 2026-01-03 | TRK-212  | T680        | DEP-FLL    | M11         | Master              |           110.00 |        2.50 | P-4403     |         4 | SUP-02
--  WO-50005      | 2026-01-04 | 2026-01-04 | TRK-205  | NRR         | DEP-TPA    | M11         | Master              |           110.00 |        1.50 | P-4430     |         3 | SUP-03
-- (5 rows)

-- Q4. Empty part slots: how many work orders leave each slot blank
SELECT count(*) FILTER (WHERE part1_code IS NULL) AS empty_slot1,
       count(*) FILTER (WHERE part2_code IS NULL) AS empty_slot2,
       count(*) FILTER (WHERE part3_code IS NULL) AS empty_slot3,
       count(*) FILTER (WHERE part4_code IS NULL) AS empty_slot4
FROM work_orders_unf;

-- Result:
--  empty_slot1 | empty_slot2 | empty_slot3 | empty_slot4 
-- -------------+-------------+-------------+-------------
--            0 |         386 |         770 |         986
-- (1 row)

-- Q5. Parts used per work order (shows the variable-length repeating group)
SELECT parts_used, count(*) AS work_orders
FROM (SELECT work_order_no,
             (part1_code IS NOT NULL)::int + (part2_code IS NOT NULL)::int
           + (part3_code IS NOT NULL)::int + (part4_code IS NOT NULL)::int AS parts_used
      FROM work_orders_unf) t
GROUP BY parts_used
ORDER BY parts_used;

-- Result:
--  parts_used | work_orders 
-- ------------+-------------
--           1 |         386
--           2 |         384
--           3 |         216
--           4 |         114
-- (4 rows)

-- Q6. Slots are filled left to right with no gaps, and a slot is never half filled
SELECT count(*) FILTER (WHERE part2_code IS NOT NULL AND part1_code IS NULL
                           OR part3_code IS NOT NULL AND part2_code IS NULL
                           OR part4_code IS NOT NULL AND part3_code IS NULL) AS gap_rows,
       count(*) FILTER (WHERE (part2_code IS NULL) <> (part2_supplier_phone IS NULL)
                           OR (part3_code IS NULL) <> (part3_supplier_phone IS NULL)
                           OR (part4_code IS NULL) <> (part4_supplier_phone IS NULL)) AS half_filled_slots
FROM work_orders_unf;

-- Result:
--  gap_rows | half_filled_slots 
-- ----------+-------------------
--         0 |                 0
-- (1 row)

-- Q7. The same part code never appears twice on one work order
SELECT count(*) AS work_orders_with_repeated_part
FROM work_orders_unf
WHERE part1_code IN (part2_code, part3_code, part4_code)
   OR part2_code IN (part3_code, part4_code)
   OR part3_code = part4_code;

-- Result:
--  work_orders_with_repeated_part 
-- --------------------------------
--                               0
-- (1 row)

-- Q8. Depot repetition: every depot value combination and how often it repeats
SELECT depot_code, depot_name, depot_city, depot_phone, count(*) AS rows
FROM work_orders_unf
GROUP BY depot_code, depot_name, depot_city, depot_phone
ORDER BY depot_code, rows DESC;

-- Result:
--  depot_code |      depot_name      |   depot_city    |  depot_phone   | rows 
-- ------------+----------------------+-----------------+----------------+------
--  DEP-DOR    | Doral Service Center | Doral           | (305) 555-0162 |  275
--  DEP-FLL    | Fort Lauderdale Yard | Fort Lauderdale | (954) 555-0118 |  266
--  DEP-FLL    | Fort Lauderdale Yard | Fort Lauderdale | (954) 555-0181 |    2
--  DEP-MIA    | Miami Main Shop      | Miami           | (305) 555-0140 |  299
--  DEP-TPA    | Tampa Bay Shop       | Tampa           | (813) 555-0175 |  258
-- (5 rows)

-- Q9. Data sanity: dates in order, labor hours range, no missing header values
SELECT count(*) FILTER (WHERE close_date < open_date) AS closed_before_opened,
       min(open_date) AS first_open, max(close_date) AS last_close,
       min(labor_hours) AS min_hours, max(labor_hours) AS max_hours,
       count(*) FILTER (WHERE truck_id IS NULL OR depot_code IS NULL OR mechanic_id IS NULL) AS missing_header
FROM work_orders_unf;

-- Result:
--  closed_before_opened | first_open | last_close | min_hours | max_hours | missing_header 
-- ----------------------+------------+------------+-----------+-----------+----------------
--                     0 | 2026-01-03 | 2026-10-06 |      0.50 |      6.00 |              0
-- (1 row)

