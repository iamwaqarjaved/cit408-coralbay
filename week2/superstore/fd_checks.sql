-- fd_checks.sql
-- CIT 408 · Assignment 2.3 · Part 2: prove the primary key and every functional dependency.
-- Pattern: GROUP BY the determinant HAVING count(DISTINCT dependent) > 1.
-- Zero rows = the dependency holds. Results captured from PostgreSQL and pasted under each query.
-- Runs in the superstore schema (first line sets the search_path), after load.sql.

SET search_path = superstore, public;

-- ============================================================
-- 1NF PRIMARY KEY
-- ============================================================
-- K1. First choice: (order_id, product_id). Is it unique?
SELECT count(*) AS duplicated_pairs
FROM (SELECT order_id, product_id FROM superstore_staging GROUP BY 1, 2 HAVING count(*) > 1) d;

-- Result:
--  duplicated_pairs 
-- ------------------
--                 8
-- (1 row)

-- K2. Look at the duplicate rows: same product listed twice on one order, different row_id
SELECT order_id, product_id, row_id, quantity, discount, sales, profit
FROM superstore_staging
WHERE (order_id, product_id) IN (SELECT order_id, product_id FROM superstore_staging GROUP BY 1, 2 HAVING count(*) > 1)
ORDER BY order_id, product_id, row_id;

-- Result:
--     order_id    |   product_id    | row_id | quantity | discount |  sales  |  profit  
-- ----------------+-----------------+--------+----------+----------+---------+----------
--  CA-2015-103135 | OFF-BI-10000069 |   6499 |        9 |        0 |  135.09 |  62.1414
--  CA-2015-103135 | OFF-BI-10000069 |   6501 |        6 |        0 |   90.06 |  41.4276
--  CA-2016-129714 | OFF-PA-10001970 |    351 |        2 |        0 |   24.56 |  11.5432
--  CA-2016-129714 | OFF-PA-10001970 |    353 |        4 |        0 |   49.12 |  23.0864
--  CA-2016-137043 | FUR-FU-10003664 |   1301 |        6 |        0 |  572.76 | 166.1004
--  CA-2016-137043 | FUR-FU-10003664 |   1302 |        3 |        0 |  286.38 |  83.0502
--  CA-2016-140571 | OFF-PA-10001954 |   9169 |       14 |        0 |  319.76 | 147.0896
--  CA-2016-140571 | OFF-PA-10001954 |   9170 |        2 |        0 |   45.68 |  21.0128
--  CA-2017-118017 | TEC-AC-10002006 |   7882 |        6 |      0.2 |  76.752 |  10.5534
--  CA-2017-118017 | TEC-AC-10002006 |   7883 |        8 |      0.2 | 102.336 |  14.0712
--  CA-2017-152912 | OFF-ST-10003208 |   3184 |        9 |        0 | 1633.14 | 473.6106
--  CA-2017-152912 | OFF-ST-10003208 |   3185 |        3 |        0 |  544.38 | 157.8702
--  US-2014-150119 | FUR-CH-10002965 |   3406 |        2 |      0.3 | 281.372 | -12.0588
--  US-2014-150119 | FUR-CH-10002965 |   3407 |        2 |      0.3 | 281.372 | -12.0588
--  US-2016-123750 | TEC-AC-10004659 |    431 |        7 |      0.2 | 408.744 |  76.6395
--  US-2016-123750 | TEC-AC-10004659 |    432 |        5 |      0.2 |  291.96 |  54.7425
-- (16 rows)

-- K3. Second choice: row_id. Unique and never NULL -> the line key
SELECT count(*) AS total_rows, count(DISTINCT row_id) AS distinct_row_ids,
       count(*) FILTER (WHERE row_id IS NULL) AS null_row_ids
FROM superstore_staging;

-- Result:
--  total_rows | distinct_row_ids | null_row_ids 
-- ------------+------------------+--------------
--        9994 |             9994 |            0
-- (1 row)

-- ============================================================
-- ORDER-LEVEL DEPENDENCIES  (order_id -> ...)
-- ============================================================
-- FD1. order_id -> order_date, ship_date, ship_mode, customer_id
SELECT order_id,
       count(DISTINCT order_date) AS n_order_date,
       count(DISTINCT ship_date) AS n_ship_date,
       count(DISTINCT ship_mode) AS n_ship_mode,
       count(DISTINCT customer_id) AS n_customer_id
FROM superstore_staging
GROUP BY order_id
HAVING count(DISTINCT order_date) > 1
    OR count(DISTINCT ship_date) > 1
    OR count(DISTINCT ship_mode) > 1
    OR count(DISTINCT customer_id) > 1;

-- Result:
--  order_id | n_order_date | n_ship_date | n_ship_mode | n_customer_id 
-- ----------+--------------+-------------+-------------+---------------
-- (0 rows)

-- FD2. order_id -> postal_code, city  (the ship-to place belongs to the ORDER)
SELECT order_id,
       count(DISTINCT postal_code) AS n_postal_code,
       count(DISTINCT city) AS n_city
FROM superstore_staging
GROUP BY order_id
HAVING count(DISTINCT postal_code) > 1
    OR count(DISTINCT city) > 1;

-- Result:
--  order_id | n_postal_code | n_city 
-- ----------+---------------+--------
-- (0 rows)

-- N1. customer_id -> postal_code does NOT hold: customers ship to many places
SELECT count(*) AS violating_groups
FROM (SELECT customer_id FROM superstore_staging GROUP BY customer_id HAVING count(DISTINCT postal_code) > 1) v;

-- Result:
--  violating_groups 
-- ------------------
--               780
-- (1 row)

-- N2. customer_id -> city does NOT hold
SELECT count(*) AS violating_groups
FROM (SELECT customer_id FROM superstore_staging GROUP BY customer_id HAVING count(DISTINCT city) > 1) v;

-- Result:
--  violating_groups 
-- ------------------
--               780
-- (1 row)

-- ============================================================
-- CUSTOMER
-- ============================================================
-- FD3. customer_id -> customer_name, segment
SELECT customer_id,
       count(DISTINCT customer_name) AS n_customer_name,
       count(DISTINCT segment) AS n_segment
FROM superstore_staging
GROUP BY customer_id
HAVING count(DISTINCT customer_name) > 1
    OR count(DISTINCT segment) > 1;

-- Result:
--  customer_id | n_customer_name | n_segment 
-- -------------+-----------------+-----------
-- (0 rows)

-- ============================================================
-- GEOGRAPHY
-- ============================================================
-- FD4. postal_code -> state
SELECT postal_code,
       count(DISTINCT state) AS n_state
FROM superstore_staging
GROUP BY postal_code
HAVING count(DISTINCT state) > 1;

-- Result:
--  postal_code | n_state 
-- -------------+---------
-- (0 rows)

-- FD5. state -> region, country
SELECT state,
       count(DISTINCT region) AS n_region,
       count(DISTINCT country) AS n_country
FROM superstore_staging
GROUP BY state
HAVING count(DISTINCT region) > 1
    OR count(DISTINCT country) > 1;

-- Result:
--  state | n_region | n_country 
-- -------+----------+-----------
-- (0 rows)

-- C1. postal_code -> city: FAILS on one postal code (see design.md, decision 3)
SELECT postal_code,
       count(DISTINCT city) AS n_city
FROM superstore_staging
GROUP BY postal_code
HAVING count(DISTINCT city) > 1;

-- Result:
--  postal_code | n_city 
-- -------------+--------
--  92024       |      2
-- (1 row)

-- C1 detail
SELECT postal_code, city, state, count(*) AS rows
FROM superstore_staging
WHERE postal_code = '92024'
GROUP BY 1, 2, 3;

-- Result:
--  postal_code |   city    |   state    | rows 
-- -------------+-----------+------------+------
--  92024       | Encinitas | California |    5
--  92024       | San Diego | California |   34
-- (2 rows)

-- N3. city -> state does NOT hold (Springfield, Columbus, ...)
SELECT count(*) AS violating_groups
FROM (SELECT city FROM superstore_staging GROUP BY city HAVING count(DISTINCT state) > 1) v;

-- Result:
--  violating_groups 
-- ------------------
--                57
-- (1 row)

-- N4. (city, state) -> postal_code does NOT hold: big cities have many postal codes
SELECT count(*) AS violating_groups
FROM (SELECT (city, state) FROM superstore_staging GROUP BY (city, state) HAVING count(DISTINCT postal_code) > 1) v;

-- Result:
--  violating_groups 
-- ------------------
--                11
-- (1 row)

-- D1. 4-digit postal codes: New England codes that lost a leading zero
SELECT count(*) AS four_digit_rows, min(postal_code), max(postal_code)
FROM superstore_staging WHERE length(postal_code) = 4;

-- Result:
--  four_digit_rows | min  | max  
-- -----------------+------+------
--              438 | 1040 | 8901
-- (1 row)

-- D2. Padding them does not merge any two codes
SELECT count(DISTINCT postal_code) AS as_loaded, count(DISTINCT lpad(postal_code, 5, '0')) AS padded
FROM superstore_staging;

-- Result:
--  as_loaded | padded 
-- -----------+--------
--        631 |    631
-- (1 row)

-- ============================================================
-- PRODUCT
-- ============================================================
-- FD6. sub_category -> category
SELECT sub_category,
       count(DISTINCT category) AS n_category
FROM superstore_staging
GROUP BY sub_category
HAVING count(DISTINCT category) > 1;

-- Result:
--  sub_category | n_category 
-- --------------+------------
-- (0 rows)

-- FD7. product_id -> sub_category, category
SELECT product_id,
       count(DISTINCT sub_category) AS n_sub_category,
       count(DISTINCT category) AS n_category
FROM superstore_staging
GROUP BY product_id
HAVING count(DISTINCT sub_category) > 1
    OR count(DISTINCT category) > 1;

-- Result:
--  product_id | n_sub_category | n_category 
-- ------------+----------------+------------
-- (0 rows)

-- C2. product_id -> product_name: FAILS for 32 product IDs (see design.md, decision 2)
SELECT count(*) AS violating_groups
FROM (SELECT product_id FROM superstore_staging GROUP BY product_id HAVING count(DISTINCT product_name) > 1) v;

-- Result:
--  violating_groups 
-- ------------------
--                32
-- (1 row)

-- C2 detail: one ID, two different products at different prices
SELECT product_id, product_name, count(*) AS rows,
       min(round(sales / quantity / (1 - discount), 2)) AS unit_price
FROM superstore_staging
WHERE product_id IN ('FUR-BO-10002213', 'FUR-CH-10001146')
GROUP BY 1, 2 ORDER BY 1, 2;

-- Result:
--    product_id    |                   product_name                   | rows | unit_price 
-- -----------------+--------------------------------------------------+------+------------
--  FUR-BO-10002213 | DMI Eclipse Executive Suite Bookcases            |    6 |     500.98
--  FUR-BO-10002213 | Sauder Forest Hills Library, Woodland Oak Finish |    4 |     140.98
--  FUR-CH-10001146 | Global Task Chair, Black                         |    5 |      50.89
--  FUR-CH-10001146 | Global Value Mid-Back Manager's Chair, Gray      |   10 |      60.89
-- (4 rows)

-- C3. product_name -> product_id also FAILS (16 names carry two IDs)
SELECT count(*) AS violating_groups
FROM (SELECT product_name FROM superstore_staging GROUP BY product_name HAVING count(DISTINCT product_id) > 1) v;

-- Result:
--  violating_groups 
-- ------------------
--                16
-- (1 row)

-- FD8. (product_id, product_name) -> sub_category, unit price: the pair IS the product
SELECT product_id, product_name
FROM superstore_staging
GROUP BY product_id, product_name
HAVING count(DISTINCT sub_category) > 1
    OR count(DISTINCT round(sales / quantity / (1 - discount), 2)) > 1;

-- Result:
--  product_id | product_name 
-- ------------+--------------
-- (0 rows)

-- ============================================================
-- LINE-LEVEL FACTS (row_id -> ...)
-- ============================================================
-- FD9. row_id -> order_id, product_id, product_name, sales, quantity, discount, profit
SELECT row_id,
       count(DISTINCT order_id) AS n_order_id,
       count(DISTINCT product_id) AS n_product_id,
       count(DISTINCT product_name) AS n_product_name,
       count(DISTINCT sales) AS n_sales,
       count(DISTINCT quantity) AS n_quantity,
       count(DISTINCT discount) AS n_discount,
       count(DISTINCT profit) AS n_profit
FROM superstore_staging
GROUP BY row_id
HAVING count(DISTINCT order_id) > 1
    OR count(DISTINCT product_id) > 1
    OR count(DISTINCT product_name) > 1
    OR count(DISTINCT sales) > 1
    OR count(DISTINCT quantity) > 1
    OR count(DISTINCT discount) > 1
    OR count(DISTINCT profit) > 1;

-- Result:
--  row_id | n_order_id | n_product_id | n_product_name | n_sales | n_quantity | n_discount | n_profit 
-- --------+------------+--------------+----------------+---------+------------+------------+----------
-- (0 rows)

-- ============================================================
-- SUMMARY
-- ============================================================
-- One row per check: 0 = holds
SELECT * FROM (VALUES
 ('K1  (order_id, product_id) unique',      (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY order_id, product_id HAVING count(*) > 1) v)),
 ('K3  row_id unique',                      (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY row_id HAVING count(*) > 1) v)),
 ('FD1 order_id -> dates, mode, customer',  (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY order_id HAVING count(DISTINCT (order_date, ship_date, ship_mode, customer_id)) > 1) v)),
 ('FD2 order_id -> postal_code, city',      (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY order_id HAVING count(DISTINCT (postal_code, city)) > 1) v)),
 ('FD3 customer_id -> name, segment',       (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY customer_id HAVING count(DISTINCT (customer_name, segment)) > 1) v)),
 ('FD4 postal_code -> state',               (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY postal_code HAVING count(DISTINCT state) > 1) v)),
 ('FD5 state -> region, country',           (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY state HAVING count(DISTINCT (region, country)) > 1) v)),
 ('FD6 sub_category -> category',           (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY sub_category HAVING count(DISTINCT category) > 1) v)),
 ('FD7 product_id -> sub_category',         (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY product_id HAVING count(DISTINCT sub_category) > 1) v)),
 ('FD8 (product_id, name) -> sub_category', (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY product_id, product_name HAVING count(DISTINCT sub_category) > 1) v)),
 ('C1  postal_code -> city',                (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY postal_code HAVING count(DISTINCT city) > 1) v)),
 ('C2  product_id -> product_name',         (SELECT count(*) FROM (SELECT 1 FROM superstore_staging GROUP BY product_id HAVING count(DISTINCT product_name) > 1) v))
) t(dependency, violating_groups);

-- Result:
--                dependency               | violating_groups 
-- ----------------------------------------+------------------
--  K1  (order_id, product_id) unique      |                8
--  K3  row_id unique                      |                0
--  FD1 order_id -> dates, mode, customer  |                0
--  FD2 order_id -> postal_code, city      |                0
--  FD3 customer_id -> name, segment       |                0
--  FD4 postal_code -> state               |                0
--  FD5 state -> region, country           |                0
--  FD6 sub_category -> category           |                0
--  FD7 product_id -> sub_category         |                0
--  FD8 (product_id, name) -> sub_category |                0
--  C1  postal_code -> city                |                1
--  C2  product_id -> product_name         |               32
-- (12 rows)

