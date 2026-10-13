# Normalization design: Coral Bay fleet work orders

**Source:** `coralbay_work_orders_unf.csv`, 1,100 rows × 46 columns
**Dependency list:** `dependencies.md` · **Proof queries:** `fd_checks.sql`

Notation: **PK** = primary key, **FK** = foreign key, **UQ** = unique (alternate key).

---

## 0. The unnormalized file (UNF)

Each row is one work order. The truck, depot, mechanic, and supplier details are copied onto every row. The parts used sit in four numbered column groups, `part1_*` through `part4_*`, each holding seven columns (code, name, unit cost, quantity, supplier ID, supplier name, supplier phone).

## 1. The 1NF problem

1NF requires that each cell hold a single value and that a table contain no repeating groups. The file breaks the second rule. "Parts used on this work order" is a list, and the file stores that list sideways, as four copies of the same seven columns. The design causes several problems:

- **The list is capped at four.** A fifth part on a repair has nowhere to go without adding seven more columns.
- **Space is wasted.** 386 work orders use only one part, so slots 2 to 4 are empty on those rows. Overall, 2,142 of the 4,400 slots (49%) are blank (`explore.sql` Q4 and Q5).
- **Queries are awkward.** Answering "every work order that used P-4430" means checking `part1_code`, `part2_code`, `part3_code`, and `part4_code`, with an `OR` across all four and a `UNION` to total the quantities.
- **The slot number carries no meaning.** Whether a part lands in slot 1 or slot 3 depends only on the order it was typed in.

**Fix:** turn each filled part slot into its own row. Rows with an empty slot are dropped. Every work order has at least one part (`part1_code` is never NULL), so no work order is lost.

### 1NF primary key

The **1NF primary key is `(work_order_no, part_code)`.**

- `work_order_no` alone is not enough: 714 work orders appear on more than one row.
- `part_code` alone is not enough: all 24 parts appear on more than one row.
- The pair never repeats, because no work order lists the same part twice (`explore.sql` Q7), and neither column is ever NULL.

I chose `part_code` over `part_slot` as the second key column because the slot number is an artifact of the spreadsheet layout. A key of `(work_order_no, part_code)` also stops the same part from being recorded twice on one order.

**Uniqueness proof (`fd_checks.sql` 0b):**

```sql
SELECT count(*)                                    AS part_lines,
       count(DISTINCT (work_order_no, part_code))  AS distinct_keys,
       count(*) FILTER (WHERE work_order_no IS NULL OR part_code IS NULL) AS null_keys
FROM wo_1nf;
--  part_lines | distinct_keys | null_keys
-- ------------+---------------+-----------
--        2258 |          2258 |         0
```

The view returns 2,258 rows and 2,258 distinct keys, with no NULLs, so the key is unique. Query 0c, a `GROUP BY ... HAVING count(*) > 1` check, returns 0 rows.

---

## 2. 1NF design

**`work_order_line`**: 2,258 rows

| Column | Key |
|---|---|
| work_order_no | **PK** (part 1) |
| part_code | **PK** (part 2) |
| open_date, close_date | |
| truck_id, truck_vin, truck_make, truck_model, truck_year | |
| depot_code, depot_name, depot_city, depot_phone | |
| mechanic_id, mechanic_name, mechanic_cert_level, cert_hourly_rate | |
| labor_hours, problem_description | |
| part_name, part_unit_cost, part_qty | |
| supplier_id, supplier_name, supplier_phone | |

- **PK:** `(work_order_no, part_code)`
- **FKs:** none, since this is a single table.
- **Remaining problems:**
  - Partial dependencies: FD2 and FD3.
  - Transitive dependencies: FD4 to FD9.
  - As a result, every work order's header data repeats on each of its part lines, and every part's supplier data repeats on every line that uses the part.

---

## 3. 2NF design

2NF removes partial dependencies, meaning columns that depend on only part of the composite key.

- **FD2:** everything that depends on `work_order_no` alone moves to `work_order`.
- **FD3:** everything that depends on `part_code` alone moves to `part`.
- **FD1:** only `part_qty` depends on the whole key, so it stays in the line table.

The supplier columns move along with `part`, because they reach the key only through `part_code`.

**`work_order`**: 1,100 rows

| Column | Key |
|---|---|
| work_order_no | **PK** |
| open_date, close_date, labor_hours, problem_description | |
| truck_id, truck_vin, truck_make, truck_model, truck_year | |
| depot_code, depot_name, depot_city, depot_phone | |
| mechanic_id, mechanic_name, mechanic_cert_level, cert_hourly_rate | |

**`part`**: 24 rows

| Column | Key |
|---|---|
| part_code | **PK** |
| part_name, part_unit_cost | |
| supplier_id, supplier_name, supplier_phone | |

**`work_order_part`**: 2,258 rows

| Column | Key |
|---|---|
| work_order_no | **PK** (part 1), **FK → work_order** |
| part_code | **PK** (part 2), **FK → part** |
| part_qty | |

Every table is now in 2NF. `work_order` and `part` have single-column keys, so a partial dependency cannot occur in them. `work_order_part` holds only `part_qty`, which depends on the full key.

They are not yet in 3NF, because transitive dependencies remain:

- `work_order` contains FD4, FD5, FD6, FD7, and FD8. For example, `depot_name` describes `depot_code`, not the work order.
- `part` contains FD9: `supplier_name` describes `supplier_id`, not the part.

---

## 4. 3NF design

3NF removes transitive dependencies, so that every non-key column describes the key, the whole key, and nothing but the key. Each transitive determinant becomes the primary key of its own table. Where a dependency chain has two links, both links get split out.

| Dependency removed | New table | What stays behind as an FK |
|---|---|---|
| FD4 `truck_id → vin, model, year` | `truck` | `work_order.truck_id` |
| FD5 `truck_model → truck_make` (2nd hop) | `truck_model` | `truck.truck_model` |
| FD6 `depot_code → name, city, phone` | `depot` | `work_order.depot_code` |
| FD7 `mechanic_id → name, cert_level` | `mechanic` | `work_order.mechanic_id` |
| FD8 `cert_level → hourly_rate` (2nd hop) | `cert_level` | `mechanic.mechanic_cert_level` |
| FD9 `supplier_id → name, phone` | `supplier` | `part.supplier_id` |

The resulting design has nine tables.

**`truck_model`**: 7 rows

| Column | Key |
|---|---|
| truck_model | **PK** |
| truck_make | |

**`truck`**: 40 rows

| Column | Key |
|---|---|
| truck_id | **PK** |
| truck_vin | **UQ** (FD10) |
| truck_model | **FK → truck_model** |
| truck_year | |

**`depot`**: 4 rows

| Column | Key |
|---|---|
| depot_code | **PK** |
| depot_name | **UQ** (FD11) |
| depot_city | |
| depot_phone | (resolved: DEP-FLL = (954) 555-0118) |

**`cert_level`**: 4 rows

| Column | Key |
|---|---|
| mechanic_cert_level | **PK** |
| cert_hourly_rate | |

**`mechanic`**: 18 rows

| Column | Key |
|---|---|
| mechanic_id | **PK** |
| mechanic_name | |
| mechanic_cert_level | **FK → cert_level** |

**`supplier`**: 4 rows

| Column | Key |
|---|---|
| supplier_id | **PK** |
| supplier_name | **UQ** (FD13) |
| supplier_phone | **UQ** (FD14) |

**`part`**: 24 rows

| Column | Key |
|---|---|
| part_code | **PK** |
| part_name | **UQ** (FD12) |
| part_unit_cost | |
| supplier_id | **FK → supplier** |

**`work_order`**: 1,100 rows

| Column | Key |
|---|---|
| work_order_no | **PK** |
| open_date, close_date | |
| truck_id | **FK → truck** |
| depot_code | **FK → depot** |
| mechanic_id | **FK → mechanic** |
| labor_hours, problem_description | |

**`work_order_part`**: 2,258 rows

| Column | Key |
|---|---|
| work_order_no | **PK** (part 1), **FK → work_order** |
| part_code | **PK** (part 2), **FK → part** |
| part_qty | |

### Relationships

| Parent → child | Cardinality | Through the FK |
|---|---|---|
| truck_model → truck | 1 : N | truck.truck_model |
| truck → work_order | 1 : N | work_order.truck_id |
| depot → work_order | 1 : N | work_order.depot_code |
| cert_level → mechanic | 1 : N | mechanic.mechanic_cert_level |
| mechanic → work_order | 1 : N | work_order.mechanic_id |
| supplier → part | 1 : N | part.supplier_id |
| work_order → work_order_part | 1 : N (at least 1) | work_order_part.work_order_no |
| part → work_order_part | 1 : N | work_order_part.part_code |

`work_order_part` is the associative entity that resolves the many-to-many relationship between `work_order` and `part`.

### Final check: every non-key column against the dependency list

This repeats the check recommended in the assignment's most-common-failure note. For each 3NF table, I asked whether any non-key column describes another non-key column rather than the key.

| Table | Non-key columns | Determined by the key only? |
|---|---|---|
| truck_model | truck_make | Yes (FD5) |
| truck | truck_vin, truck_model, truck_year | Yes (FD4). `truck_make` is not here, because it would describe `truck_model`. |
| depot | depot_name, depot_city, depot_phone | Yes (FD6). Name to city holds in the data, but each depot has one name, so `depot_name` is a candidate key (FD11) and not a transitive determinant. |
| cert_level | cert_hourly_rate | Yes (FD8) |
| mechanic | mechanic_name, mechanic_cert_level | Yes (FD7). `cert_hourly_rate` is not here, because it would describe `mechanic_cert_level`. |
| supplier | supplier_name, supplier_phone | Yes (FD9). Both are candidate keys of the same supplier. |
| part | part_name, part_unit_cost, supplier_id | Yes (FD3). `supplier_name` and `supplier_phone` are not here, because they would describe `supplier_id`. |
| work_order | open_date, close_date, truck_id, depot_code, mechanic_id, labor_hours, problem_description | Yes (FD2). None of these determines another. N1 to N3 show that `mechanic_id`, `truck_id`, and `problem_description` do not determine depot or hours. |
| work_order_part | part_qty | Yes, by the full key (FD1) |

No non-key column depends on another non-key column, so the design is in **3NF**. Every determinant is also a candidate key of its own table, so the design meets BCNF too.

### Lossless-join check

As an extra check, I built the nine tables in PostgreSQL 16, loaded them from the 1NF view, and joined them back together. The join returns 2,258 rows. The only rows that differ from the original are the 5 part lines on WO-50041 and WO-50047, and they differ only in the corrected Fort Lauderdale phone number. No information is lost or invented.

### Design notes

- **`part_slot` is dropped.** The slot number records the order of entry in the spreadsheet and has no business meaning. If line order ever matters, a `line_no` column could be added to `work_order_part`.
- **Current-value pricing.** In this file, `part_unit_cost` and `cert_hourly_rate` never vary for a given part or certification level, so each is stored once. If Coral Bay later needs invoices that keep the price in effect on the day of the repair, those prices would be copied onto `work_order_part` and `work_order` deliberately as historical snapshots. That would not be a normalization violation.
