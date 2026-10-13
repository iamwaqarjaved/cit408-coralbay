-- load_data.sql
-- CIT 408 · Assignment 2.3 · Part 3: fill the 3NF tables from superstore_staging.
-- Parent tables first, child tables last. Run after create_tables.sql.
-- Cleaning applied on the way in:
--   * postal codes padded to 5 digits (1841 -> 01841)
--   * M/D/YYYY text dates converted with to_date()

SET search_path = superstore, public;

BEGIN;

INSERT INTO region (region)
SELECT DISTINCT region FROM superstore_staging;

INSERT INTO state (state, region, country)
SELECT DISTINCT state, region, country FROM superstore_staging;

INSERT INTO postal_area (postal_code, state)
SELECT DISTINCT lpad(postal_code, 5, '0'), state FROM superstore_staging;

INSERT INTO ship_location (postal_code, city)
SELECT DISTINCT lpad(postal_code, 5, '0'), city FROM superstore_staging;

INSERT INTO customer (customer_id, customer_name, segment)
SELECT DISTINCT customer_id, customer_name, segment FROM superstore_staging;

INSERT INTO category (category)
SELECT DISTINCT category FROM superstore_staging;

INSERT INTO sub_category (sub_category, category)
SELECT DISTINCT sub_category, category FROM superstore_staging;

INSERT INTO product (product_id, product_name, sub_category)
SELECT DISTINCT product_id, product_name, sub_category FROM superstore_staging
ORDER BY product_id, product_name;

INSERT INTO orders (order_id, order_date, ship_date, ship_mode, customer_id, postal_code, city)
SELECT DISTINCT order_id,
       to_date(order_date, 'MM/DD/YYYY'),
       to_date(ship_date,  'MM/DD/YYYY'),
       ship_mode, customer_id, lpad(postal_code, 5, '0'), city
FROM superstore_staging;

INSERT INTO order_line (line_id, order_id, product_key, sales, quantity, discount, profit)
SELECT s.row_id, s.order_id, p.product_key, s.sales, s.quantity, s.discount, s.profit
FROM superstore_staging s
JOIN product p ON p.product_id = s.product_id AND p.product_name = s.product_name;

COMMIT;

SELECT 'order_line' AS table_name, count(*) AS rows_loaded FROM order_line;
