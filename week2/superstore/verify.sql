-- verify.sql
-- CIT 408 · Assignment 2.3 · Part 4: prove the 3NF database works.
-- Runs in the superstore schema (first line sets the search_path), after create_tables.sql and load_data.sql.
-- Results captured from PostgreSQL and pasted under each query.
-- In pgAdmin, run query V5 last: it is meant to fail, and the error stops a full-file run.

SET search_path = superstore, public;

-- V1. Row count of every table
SELECT 'region' AS table_name, count(*) AS row_count FROM region
UNION ALL SELECT 'state',         count(*) FROM state
UNION ALL SELECT 'postal_area',   count(*) FROM postal_area
UNION ALL SELECT 'ship_location', count(*) FROM ship_location
UNION ALL SELECT 'customer',      count(*) FROM customer
UNION ALL SELECT 'category',      count(*) FROM category
UNION ALL SELECT 'sub_category',  count(*) FROM sub_category
UNION ALL SELECT 'product',       count(*) FROM product
UNION ALL SELECT 'orders',        count(*) FROM orders
UNION ALL SELECT 'order_line',    count(*) FROM order_line;

-- Result:
--   table_name   | row_count 
-- ---------------+-----------
--  region        |         4
--  state         |        49
--  postal_area   |       631
--  ship_location |       632
--  customer      |       793
--  category      |         3
--  sub_category  |        17
--  product       |      1894
--  orders        |      5009
--  order_line    |      9994
-- (10 rows)

-- V2. Join all 10 tables back together: one row per order line (expect 9994)
SELECT count(*) AS joined_lines
FROM order_line    ol
JOIN orders        o  ON o.order_id     = ol.order_id
JOIN customer      c  ON c.customer_id  = o.customer_id
JOIN ship_location sl ON sl.postal_code = o.postal_code AND sl.city = o.city
JOIN postal_area   pa ON pa.postal_code = sl.postal_code
JOIN state         st ON st.state       = pa.state
JOIN region        r  ON r.region       = st.region
JOIN product       p  ON p.product_key  = ol.product_key
JOIN sub_category  sc ON sc.sub_category = p.sub_category
JOIN category      ca ON ca.category    = sc.category;

-- Result:
--  joined_lines 
-- --------------
--          9994
-- (1 row)

-- V2b. The rejoined rows match the staging file exactly, column for column (expect 0 and 0)
WITH rebuilt AS (
  SELECT ol.line_id, o.order_id, o.order_date, o.ship_date, o.ship_mode,
         c.customer_id, c.customer_name, c.segment, st.country, sl.city, st.state,
         sl.postal_code, r.region, p.product_id, ca.category, sc.sub_category, p.product_name,
         ol.sales, ol.quantity, ol.discount, ol.profit
  FROM order_line ol
  JOIN orders o         ON o.order_id = ol.order_id
  JOIN customer c       ON c.customer_id = o.customer_id
  JOIN ship_location sl ON sl.postal_code = o.postal_code AND sl.city = o.city
  JOIN postal_area pa   ON pa.postal_code = sl.postal_code
  JOIN state st         ON st.state = pa.state
  JOIN region r         ON r.region = st.region
  JOIN product p        ON p.product_key = ol.product_key
  JOIN sub_category sc  ON sc.sub_category = p.sub_category
  JOIN category ca      ON ca.category = sc.category),
staged AS (
  SELECT row_id, order_id, to_date(order_date, 'MM/DD/YYYY'), to_date(ship_date, 'MM/DD/YYYY'), ship_mode,
         customer_id, customer_name, segment, country, city, state,
         lpad(postal_code, 5, '0'), region, product_id, category, sub_category, product_name,
         sales, quantity, discount, profit
  FROM superstore_staging)
SELECT (SELECT count(*) FROM (SELECT * FROM staged  EXCEPT ALL SELECT * FROM rebuilt) a) AS only_in_staging,
       (SELECT count(*) FROM (SELECT * FROM rebuilt EXCEPT ALL SELECT * FROM staged)  b) AS only_in_3nf;

-- Result:
--  only_in_staging | only_in_3nf 
-- -----------------+-------------
--                0 |           0
-- (1 row)

-- V3. Total sales: joined 3NF tables vs staging (must match)
SELECT (SELECT sum(sales) FROM superstore_staging) AS staging_total_sales,
       (SELECT sum(ol.sales)
        FROM order_line ol
        JOIN orders o  ON o.order_id = ol.order_id
        JOIN product p ON p.product_key = ol.product_key) AS joined_total_sales,
       (SELECT sum(sales) FROM superstore_staging) =
       (SELECT sum(ol.sales) FROM order_line ol
        JOIN orders o  ON o.order_id = ol.order_id
        JOIN product p ON p.product_key = ol.product_key) AS totals_match;

-- Result:
--  staging_total_sales | joined_total_sales | totals_match 
-- ---------------------+--------------------+--------------
--         2297200.8603 |       2297200.8603 | t
-- (1 row)

-- V4. Constraint inventory: every PK, FK and CHECK that was created
SELECT conrelid::regclass AS table_name,
       CASE contype WHEN 'p' THEN 'PRIMARY KEY' WHEN 'f' THEN 'FOREIGN KEY'
                    WHEN 'c' THEN 'CHECK' WHEN 'u' THEN 'UNIQUE' END AS constraint_type,
       count(*) AS how_many
FROM pg_constraint
WHERE connamespace = 'superstore'::regnamespace AND contype IN ('p', 'f', 'c', 'u')
GROUP BY 1, 2
ORDER BY 2, conrelid::regclass::text;

-- Result:
--   table_name   | constraint_type | how_many 
-- ---------------+-----------------+----------
--  customer      | CHECK           |        1
--  order_line    | CHECK           |        3
--  orders        | CHECK           |        2
--  postal_area   | CHECK           |        1
--  order_line    | FOREIGN KEY     |        2
--  orders        | FOREIGN KEY     |        2
--  postal_area   | FOREIGN KEY     |        1
--  product       | FOREIGN KEY     |        1
--  ship_location | FOREIGN KEY     |        1
--  state         | FOREIGN KEY     |        1
--  sub_category  | FOREIGN KEY     |        1
--  category      | PRIMARY KEY     |        1
--  customer      | PRIMARY KEY     |        1
--  order_line    | PRIMARY KEY     |        1
--  orders        | PRIMARY KEY     |        1
--  postal_area   | PRIMARY KEY     |        1
--  product       | PRIMARY KEY     |        1
--  region        | PRIMARY KEY     |        1
--  ship_location | PRIMARY KEY     |        1
--  state         | PRIMARY KEY     |        1
--  sub_category  | PRIMARY KEY     |        1
--  product       | UNIQUE          |        1
-- (22 rows)

-- V5. Foreign key test: add a line for a product that does not exist (product_key 999999).
--     Expected: ERROR, insert or update violates foreign key constraint.
INSERT INTO order_line (line_id, order_id, product_key, sales, quantity, discount, profit)
VALUES (10001, 'CA-2016-152156', 999999, 100.00, 1, 0, 10.00);

-- Result:
-- ERROR:  insert or update on table "order_line" violates foreign key constraint "order_line_product_key_fkey"
-- DETAIL:  Key (product_key)=(999999) is not present in table "product".

