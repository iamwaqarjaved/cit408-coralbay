# Functional dependencies: Coral Bay fleet work orders

**1NF table:** `work_order_line`, one row for each part used on a work order (2,258 rows).
**1NF primary key:** `(work_order_no, part_code)`

Labels are relative to that key:

- **Full**: the column depends on the whole composite key and on neither half alone.
- **Partial**: the column depends on only one column of the key. This breaks 2NF.
- **Transitive**: the column depends on a non-key column, which in turn depends on the key. This breaks 3NF.

Each FD number matches a proof query in `fd_checks.sql`.

## Primary dependency list

| # | Determinant | Dependent columns | Label | Chain back to the key |
|---|---|---|---|---|
| FD1 | `(work_order_no, part_code)` | `part_qty` | **Full** | Neither half alone works: 602 work orders and 24 parts show more than one quantity |
| FD2 | `work_order_no` | `open_date`, `close_date`, `truck_id`, `depot_code`, `mechanic_id`, `labor_hours`, `problem_description` | **Partial** | Depends on the left half of the key only |
| FD3 | `part_code` | `part_name`, `part_unit_cost`, `supplier_id` | **Partial** | Depends on the right half of the key only |
| FD4 | `truck_id` | `truck_vin`, `truck_model`, `truck_year` | **Transitive** | `work_order_no → truck_id → …` |
| FD5 | `truck_model` | `truck_make` | **Transitive (2nd hop)** | `work_order_no → truck_id → truck_model → truck_make` |
| FD6 | `depot_code` | `depot_name`, `depot_city`, `depot_phone` | **Transitive** | `work_order_no → depot_code → …` *(one conflicting value; see below)* |
| FD7 | `mechanic_id` | `mechanic_name`, `mechanic_cert_level` | **Transitive** | `work_order_no → mechanic_id → …` |
| FD8 | `mechanic_cert_level` | `cert_hourly_rate` | **Transitive (2nd hop)** | `work_order_no → mechanic_id → mechanic_cert_level → cert_hourly_rate` |
| FD9 | `supplier_id` | `supplier_name`, `supplier_phone` | **Transitive** | `part_code → supplier_id → …` (also a partial dependency on the key) |

### The two-hop chains

Two chains have a second link, and stopping early would leave a 3NF violation in place:

1. **`truck_make`** depends on `truck_id`, but only by way of `truck_model`. Every Cascadia is a Freightliner and every 579 is a Peterbilt. If `truck_make` stayed in `truck`, it would describe the non-key column `truck_model`. It therefore moves into its own `truck_model` table.
2. **`cert_hourly_rate`** depends on `mechanic_id`, but only by way of `mechanic_cert_level`. All six Level 1 mechanics earn $58.00 and all six Master mechanics earn $110.00. If the rate stayed in `mechanic`, it would describe the non-key column `mechanic_cert_level`. It therefore moves into a `cert_level` table.

The part-to-supplier chain works the same way: `part_code → supplier_id → supplier_name, supplier_phone`. The supplier's name and phone go in `supplier`, not in `part`.

## Alternate-key dependencies (kept as UNIQUE constraints)

These columns identify their entity just as well as the chosen key does. They do not create new tables, but each one becomes a `UNIQUE` constraint.

| # | Determinant | Dependent | Label | Meaning |
|---|---|---|---|---|
| FD10 | `truck_vin` | `truck_id` (and all truck columns) | Transitive | A VIN uniquely identifies a vehicle in the real world |
| FD11 | `depot_name` | `depot_code` | Transitive | Each depot has one name |
| FD12 | `part_name` | `part_code` | Non-key → key column | Each part name appears in the catalog once |
| FD13 | `supplier_name` | `supplier_id` | Transitive | Each supplier has one name |
| FD14 | `supplier_phone` | `supplier_id` | Transitive | Each supplier has one phone |

`depot_phone → depot_code` also holds, and it becomes a candidate key once the conflict is fixed. I do not enforce it, because a depot changing its phone number should not require a key change.

## Hold in this sample, rejected on business meaning

These pass the GROUP BY test (queries R1 to R4), but they happen to be true for this data and are not business rules. Enforcing them would block valid future data.

| # | Determinant → dependent | Why it is rejected |
|---|---|---|
| R1 | `truck_make → truck_model` | The fleet happens to own one model per make, but a manufacturer builds many models. The real rule runs the other way (FD5). |
| R2 | `cert_hourly_rate → mechanic_cert_level` | Two certification levels could one day share a pay rate. The rate describes the level, not the reverse. |
| R3 | `mechanic_name → mechanic_id` | Two mechanics could share a name, which is why `mechanic_id` exists. |
| R4 | `depot_city → depot_code` | A second depot could open in the same city. |

## Candidate dependencies that do NOT hold

Each of these was tested and fails (queries N1 to N3), so none of these columns moves into the other's table.

| Candidate | Result | Consequence |
|---|---|---|
| `mechanic_id → depot_code` | All 18 mechanics appear at more than one depot | `depot_code` stays on `work_order` and does not go on `mechanic` |
| `truck_id → depot_code` | All 40 trucks are serviced at more than one depot | `depot_code` stays on `work_order` and does not go on `truck` |
| `problem_description → labor_hours` | All 12 problem types show varying hours | `labor_hours` is a fact about the individual work order |

## The conflicting value

**FD6 is the one check that returns a row.** `DEP-FLL` (Fort Lauderdale Yard) has two phone numbers:

| depot_phone | Work orders |
|---|---|
| (954) 555-**0118** | 266 |
| (954) 555-**0181** | 2 (WO-50041 on 2026-01-13, WO-50047 on 2026-01-14) |

The name and city of `DEP-FLL` are consistent everywhere, and no other depot has a second phone.

**Resolution rule: majority value per determinant.** When a determinant has more than one value for a dependent, the value on the most rows wins. A tie is not resolved automatically and gets flagged for manual review. `DEP-FLL` therefore keeps **(954) 555-0118**.

Why this rule fits here:

- **The evidence is one-sided.** The two variant rows are 0.7% of Fort Lauderdale's 268 work orders, and they sit two days apart in mid-January. That looks like a short-lived data-entry mistake, not a change of number.
- **The variant looks like a typo.** 0181 is 0118 with the last two digits swapped, a common keying error.
- **It is not a real change of number.** If the depot had changed numbers, the new value would continue from some date onward. Instead, work orders after January 14 go back to 0118.
- **It is what normalization requires.** A depot has one phone number. In 3NF the phone is stored once, in `depot`, so the two copies cannot both be kept.
- **The rule is repeatable.** The same query, C3 in `fd_checks.sql`, resolves any future conflict the same way, and C4 shows FD6 holds once the rule is applied.

Nothing is deleted. WO-50041 and WO-50047 remain intact, and they get the corrected phone through their `depot_code` foreign key.
