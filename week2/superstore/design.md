# Superstore normalization design

**Source:** `Superstore.csv`, 9,994 order lines × 21 columns, U.S. office-supply retailer, orders dated 2014 to 2017
**Proof queries:** `fd_checks.sql`. Every dependency below has a `GROUP BY … HAVING count(DISTINCT …) > 1` query there, with its result pasted underneath.

---

## 0. Loading the file

**Where it lives:** a schema called `superstore` inside the `coralbay` database, not a separate database. A schema gives the 3NF tables, keys and ERD their own namespace, kept apart from the Week 2 work-order tables in `public`. Every script begins with `SET search_path = superstore, public;`.

The file is **Windows-1252**, not UTF-8. It contains curly quotes (bytes `0x93`/`0x94`) and non-breaking spaces (`0xA0`). A plain `\copy` stops with `invalid byte sequence for encoding "UTF8": 0xa0`. Loading it with `ENCODING 'WIN1252'` converts every character correctly, and all 9,994 rows load.

The staging table keeps both dates as `text`, because the file writes them as `M/D/YYYY`. They are converted with `to_date()` when the 3NF tables are filled.

`postal_code` is also kept as `text`, for two reasons. A postal code is a label, not a number. And **438 rows** hold 4-digit New England codes such as `1841`, which lost their leading zero on the way out of a spreadsheet. An integer column would hide that problem. The load pads them back to 5 digits (`01841`). Query D2 shows that padding doesn't merge any two codes: there are 631 distinct codes before and after.

---

## 1. The primary key of the line table

| Candidate | Unique? | Evidence |
|---|---|---|
| `(order_id, product_id)` | **No**, 8 pairs repeat | Query K1 |
| `row_id` | **Yes**, 9,994 distinct values and no NULLs | Query K3 |

My first choice was `(order_id, product_id)`, on the reasoning that one product appears once per order. It failed. Query K2 lists the 16 rows behind the 8 duplicate pairs. In each pair the same product appears twice on one order, as two separate lines with their own quantities, for example 9 units and then 6 units of `OFF-BI-10000069` on `CA-2015-103135`.

In seven of the eight pairs the two lines differ, so they are real separate lines. One pair (`US-2014-150119`, rows 3406 and 3407) is identical in every column except `row_id`. It could be a double entry, but nothing in the file proves that, so I kept it.

**Decision: the line key is `row_id`, stored as `line_id`.** It is the only column that identifies a line. Keeping it means no line is merged or lost, so the 3NF database holds all 9,994 lines and the sales total matches the file exactly.

---

## 2. Functional dependencies

Labels are relative to the 1NF key `line_id`. A dependency on the order or the product, rather than the line, is **transitive**: `line_id → order_id → order_date`.

### Dependencies that hold (0 violating groups)

| # | Determinant → dependent | Kind | Goes to table |
|---|---|---|---|
| FD9 | `line_id → order_id, product, sales, quantity, discount, profit` | Full (single-column key) | `order_line` |
| FD1 | `order_id → order_date, ship_date, ship_mode, customer_id` | Transitive through `order_id` | `orders` |
| FD2 | `order_id → postal_code, city` | Transitive through `order_id` | `orders` (FK to `ship_location`) |
| FD3 | `customer_id → customer_name, segment` | Transitive: line → order → customer | `customer` |
| FD4 | `postal_code → state` | Transitive: order → postal code → state | `postal_area` |
| FD5 | `state → region, country` | Transitive: postal code → state → region (3rd hop) | `state` |
| FD6 | `sub_category → category` | Transitive: product → sub-category → category | `sub_category` |
| FD8 | `(product_id, product_name) → sub_category` | Transitive through the product | `product` |

### Checks that fail, and what I decided

**Decision 1: the ship-to location belongs to the order, not the customer (queries N1 and N2).**
Going by the column names, the location would describe the customer. The data says it doesn't. **780 of the 793 customers** have orders shipped to more than one postal code, while every order has exactly one ship-to place (FD2). So `postal_code` and `city` go on `orders`, not on `customer`. This is the trap the assignment warns about: "the location columns may not describe the thing you expect."

**Decision 2: `product_id` does not identify a product (queries C2, C3 and FD8).**
**32 product IDs** each carry two different product names. For example, `FUR-BO-10002213` is both "DMI Eclipse Executive Suite Bookcases" at a unit price of $500.98 and "Sauder Forest Hills Library" at $140.98. These are genuinely different products with different prices, not a spelling variation. The reverse check also fails: **16 product names** carry two IDs.

The pair `(product_id, product_name)` does behave like one product. It always has one sub-category and one unit price. So the `product` table gets a **surrogate key `product_key`**, and `UNIQUE (product_id, product_name)` keeps the real-world pair from repeating. That gives 1,894 products instead of 1,862 IDs. I didn't pick one name per ID by majority, because that would have attached sales lines to the wrong product.

**Decision 3: a postal code can cover two cities (query C1).**
`postal_code → city` fails on one code: `92024` appears as San Diego (34 rows) and as Encinitas (5 rows). Postal code 92024 really is Encinitas, a city inside San Diego County, so both labels are plausible addresses for the same place. Rather than change 34 rows of source data, I model a **ship-to place as `(postal_code, city)`**. The postal code alone still determines the state (FD4, which holds), so the state goes in `postal_area`, and `ship_location` holds the valid city names within each code. This gives 632 ship locations across 631 postal codes.

**Other candidates that don't hold.** These are why some columns are *not* used as keys:
- `city → state` fails for 57 cities (there are Springfields and Columbuses in several states). City is never used alone.
- `(city, state) → postal_code` fails for 11 cities, because large cities have many codes.

`customer_name → customer_id` holds in this sample, but two people can share a name, so I don't enforce it as a rule. `country` has a single value ("United States"). It is stored once per state, which keeps the design correct if the store ever ships to another country.

---

## 3. 1NF design

Every cell already holds a single value, so the file has no multi-valued cells and no repeating groups. 1NF only needs a key.

**`line_1nf`**: 9,994 rows, **PK `line_id`**

`line_id, order_id, order_date, ship_date, ship_mode, customer_id, customer_name, segment, country, city, state, postal_code, region, product_id, product_name, category, sub_category, sales, quantity, discount, profit`

The 1NF problem here isn't the shape of the data, it's the redundancy. An order with 4 lines stores its date, customer and address 4 times, and a customer's name repeats on every line they ever bought.

## 4. 2NF design

The key is a single column (`line_id`), so **no partial dependency is possible**, and the 1NF table is already in 2NF.

The real redundancy is transitive, so all the splitting happens in 3NF. If I had kept the composite key `(order_id, product_id)`, the order and product columns would have been partial dependencies, and they would have moved out at this step instead. The final tables would be the same.

## 5. 3NF design

Each transitive determinant becomes the key of its own table, and the key stays behind as a foreign key. There are three chains of three links each, and I followed every one to its end:

- `line → order → customer → name, segment`
- `line → order → postal_code → state → region`
- `line → product → sub_category → category`

**PK** = primary key, **FK** = foreign key, **UQ** = unique.

| Table | Columns | PK | FKs | Rows |
|---|---|---|---|---|
| `region` | region | region | | 4 |
| `state` | state, region, country | state | region → region | 49 |
| `postal_area` | postal_code, state | postal_code | state → state | 631 |
| `ship_location` | postal_code, city | (postal_code, city) | postal_code → postal_area | 632 |
| `customer` | customer_id, customer_name, segment | customer_id | | 793 |
| `category` | category | category | | 3 |
| `sub_category` | sub_category, category | sub_category | category → category | 17 |
| `product` | product_key, product_id, product_name, sub_category | product_key, with UQ on (product_id, product_name) | sub_category → sub_category | 1,894 |
| `orders` | order_id, order_date, ship_date, ship_mode, customer_id, postal_code, city | order_id | customer_id → customer; (postal_code, city) → ship_location | 5,009 |
| `order_line` | line_id, order_id, product_key, sales, quantity, discount, profit | line_id | order_id → orders; product_key → product | 9,994 |

### Final check: every non-key column against the dependency list

| Table | Non-key column | Depends on the key, and only the key? |
|---|---|---|
| state | region, country | Yes (FD5) |
| postal_area | state | Yes (FD4). `region` isn't here, because it describes `state`. |
| customer | customer_name, segment | Yes (FD3). Location isn't here, because it varies by order (N1). |
| sub_category | category | Yes (FD6) |
| product | product_id, product_name, sub_category | Yes (FD8). `category` isn't here, because it describes `sub_category`. |
| orders | dates, ship_mode, customer_id, postal_code, city | Yes (FD1, FD2). `state` and `region` aren't here, because they describe `postal_code`. Customer name isn't here, because it describes `customer_id`. |
| order_line | sales, quantity, discount, profit | Yes (FD9). These are facts about one line. |

No non-key column describes another non-key column, so the design is in **3NF**.

### Design notes

- **`sales` and `profit` are stored as given.** In this data `sales = unit_price × quantity × (1 − discount)`, and FD8 shows the unit price is fixed per product. I still keep `sales` on the line, because it is the amount actually billed, and recomputing it would introduce rounding differences against the file.
- **`ship_mode` and `segment` stay as checked columns** instead of lookup tables. Each has a fixed list of values (4 and 3), enforced with `CHECK … IN (…)`.
- **The table is called `orders`**, because `ORDER` is a reserved word in SQL.

### Constraints (create_tables.sql)

- **Primary key:** every table has one.
- **Foreign keys:** 9, so every child table points to its parent.
- **NOT NULL:** on every column whose value is required.
- **CHECK constraints (7):**
  - `quantity > 0`
  - `sales > 0`
  - `discount` between 0 and 1 (exclusive of 1)
  - `ship_date >= order_date`
  - `ship_mode` must be one of the 4 known values
  - `segment` must be one of the 3 known values
  - `postal_code` must be 5 digits
