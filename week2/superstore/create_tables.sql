-- create_tables.sql
-- CIT 408 · Assignment 2.3 · Part 3: the 3NF design from design.md as PostgreSQL tables.
-- Runs in the superstore schema. Parent tables are created before child tables.
-- Re-runnable: drops the 3NF tables first (the staging table is left alone).

SET search_path = superstore, public;

DROP TABLE IF EXISTS order_line, orders, product, sub_category, category,
                     customer, ship_location, postal_area, state, region CASCADE;

-- Geography ---------------------------------------------------------------
CREATE TABLE region (
    region   varchar(10) PRIMARY KEY
);

CREATE TABLE state (
    state    varchar(30) PRIMARY KEY,
    region   varchar(10) NOT NULL REFERENCES region (region),
    country  varchar(30) NOT NULL
);

-- postal_code -> state holds; postal_code -> city does not (92024 = San Diego and Encinitas)
CREATE TABLE postal_area (
    postal_code  char(5) PRIMARY KEY CHECK (postal_code ~ '^[0-9]{5}$'),
    state        varchar(30) NOT NULL REFERENCES state (state)
);

-- A ship-to place is a city within a postal code
CREATE TABLE ship_location (
    postal_code  char(5)     NOT NULL REFERENCES postal_area (postal_code),
    city         varchar(40) NOT NULL,
    PRIMARY KEY (postal_code, city)
);

-- Customers ---------------------------------------------------------------
CREATE TABLE customer (
    customer_id    varchar(10) PRIMARY KEY,
    customer_name  varchar(60) NOT NULL,
    segment        varchar(15) NOT NULL
                   CHECK (segment IN ('Consumer', 'Corporate', 'Home Office'))
);

-- Products ----------------------------------------------------------------
CREATE TABLE category (
    category  varchar(20) PRIMARY KEY
);

CREATE TABLE sub_category (
    sub_category  varchar(20) PRIMARY KEY,
    category      varchar(20) NOT NULL REFERENCES category (category)
);

-- Product ID is NOT unique in the file (32 IDs name two different products),
-- so the product gets a surrogate key and the real-world pair is kept UNIQUE.
CREATE TABLE product (
    product_key   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id    varchar(20)  NOT NULL,
    product_name  varchar(200) NOT NULL,
    sub_category  varchar(20)  NOT NULL REFERENCES sub_category (sub_category),
    UNIQUE (product_id, product_name)
);

-- Orders ------------------------------------------------------------------
CREATE TABLE orders (
    order_id     varchar(20) PRIMARY KEY,
    order_date   date        NOT NULL,
    ship_date    date        NOT NULL,
    ship_mode    varchar(20) NOT NULL
                 CHECK (ship_mode IN ('Same Day', 'First Class', 'Second Class', 'Standard Class')),
    customer_id  varchar(10) NOT NULL REFERENCES customer (customer_id),
    postal_code  char(5)     NOT NULL,
    city         varchar(40) NOT NULL,
    FOREIGN KEY (postal_code, city) REFERENCES ship_location (postal_code, city),
    CHECK (ship_date >= order_date)
);

CREATE TABLE order_line (
    line_id      integer       PRIMARY KEY,          -- Row ID from the file
    order_id     varchar(20)   NOT NULL REFERENCES orders (order_id),
    product_key  integer       NOT NULL REFERENCES product (product_key),
    sales        numeric(12,4) NOT NULL CHECK (sales > 0),
    quantity     integer       NOT NULL CHECK (quantity > 0),
    discount     numeric(3,2)  NOT NULL CHECK (discount >= 0 AND discount < 1),
    profit       numeric(12,4) NOT NULL
);

-- Indexes on foreign keys used by joins (PostgreSQL does not create these automatically)
CREATE INDEX ON order_line (order_id);
CREATE INDEX ON order_line (product_key);
CREATE INDEX ON orders (customer_id);
