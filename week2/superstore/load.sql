-- load.sql
-- CIT 408 · Assignment 2.3 · Part 1: create the schema, the staging table, and load Superstore.csv
--
-- The work lives in a schema called superstore (inside the coralbay database) rather than a
-- separate database: a schema gives the same isolated namespace for tables, keys and the ERD.
--
-- pgAdmin: open a Query Tool on the coralbay database, run steps 1-2, then load the CSV with
--   right-click superstore > Tables > superstore_staging > Import/Export Data
--   (Import, Format csv, Header ON, Encoding WIN1252), then run step 4.
-- psql: run from the folder that contains Superstore.csv:  psql -d coralbay -f load.sql

-- 1. Schema -----------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS superstore;
SET search_path = superstore, public;

-- 2. Staging table: one column per CSV column, holding values as they arrive.
--    Dates stay text because the file uses M/D/YYYY; they are converted with
--    to_date() when the 3NF tables are loaded. Postal code is text, not int:
--    it is a label, and 438 rows are 4-digit New England codes that lost their
--    leading zero (1841 should be 01841), which an int column would hide.
DROP TABLE IF EXISTS superstore_staging;
CREATE TABLE superstore_staging (
    row_id         integer,
    order_id       text,
    order_date     text,
    ship_date      text,
    ship_mode      text,
    customer_id    text,
    customer_name  text,
    segment        text,
    country        text,
    city           text,
    state          text,
    postal_code    text,
    region         text,
    product_id     text,
    category       text,
    sub_category   text,
    product_name   text,
    sales          numeric,
    quantity       integer,
    discount       numeric,
    profit         numeric
);

-- 3. Load. The file is NOT UTF-8: it is Windows-1252. Bytes 0x93/0x94 are
--    curly quotes and 0xA0 is a non-breaking space, so a plain \copy fails with
--    'invalid byte sequence for encoding "UTF8": 0xa0'. Telling PostgreSQL the
--    real encoding converts every character correctly.
\copy superstore.superstore_staging FROM 'Superstore.csv' WITH (FORMAT csv, HEADER true, ENCODING 'WIN1252')

-- 4. Confirm: must be 9994
SELECT count(*) AS rows_loaded FROM superstore_staging;
