# Final Independent Verification & Acceptance Audit Report
## Railway Reservation and Passenger Service Management System

**Target Project:** Case Study 6 (BCSE302P Database Systems Lab)  
**Repository:** `https://github.com/shrey1-1/railway-reservation-dbms`  
**Review Date:** October 25, 2026  
**Auditor Role:** Independent Principal Database Engineer & QA Auditor  
**Engine:** Oracle AI Database 26ai Free Release 23.26.0.0.0 (`FREEPDB1`)  
**Verdict:** **PASS — All applicable criteria independently verified with concrete database evidence.**

---

## 1. Baseline and Environment Verification

* **Repository Working Tree:** Verified on branch `main` at commit `80ea3f94d106c0b3ec77658e6a01c88567c15f62`.
* **Database Instance:** Live Oracle AI Database 26ai Free running locally on Windows (listener on `localhost:1521`, service `FREEPDB1`).
* **Environment Isolation:** Testing executed across dedicated, disposable schemas:
  * Baseline testing: `RAILWAY_TEST`
  * Clean-room modular verification: `RAILWAY_MODULAR`
  * Clean-room consolidated verification: `RAILWAY_CONSOLIDATED`
* **Artifact Integrity:** All existing files were preserved without destructive git operations or overwrite of unrelated files.

---

## 2. Independent Verification of Findings D1–D9

Each claimed remediation from the previous audit was independently reproduced and challenged:

| Finding ID | Location | Claimed Remediation | Independent Verification Method | Actual Result | Status | Remaining Risk |
|---|---|---|---|---|---|---|
| **D1: Test 5.5 Date Sensitivity** | `parts/03_dml.sql` (Line 119), `railway_case_study6.sql` (Line 1461) | Supply explicit valid `booking_date = DATE '2026-10-20'` so trigger passes and `CK_RES_SEAT_STATUS` is tested directly. | Executed statement on post-Oct 21 test date. Checked exact Oracle error code. | Raised `ORA-02290: check constraint (CK_RES_SEAT_STATUS) violated`. Trigger `ORA-20004` bypassed cleanly. | **PASS** | None. Test is date-independent. |
| **D2: `book_ticket` Concurrency & Infinite Loop** | `parts/03_dml.sql` (Lines 140–245), `railway_case_study6.sql` (Lines 1488–1590) | Row lock on schedule (`FOR UPDATE`), active passenger check (`-20017`), bounded retry loop catching `DUP_VAL_ON_INDEX`. | Tested multi-session concurrent execution on final seat; tested duplicate active passenger booking. | Simultaneous requests: 1 confirmed, 1 waitlisted; duplicate passenger rejected with `-20017` in 1st cycle without infinite retry. | **PASS** | None under current journey booking scope. |
| **D3: `cancel_ticket` Waitlist Promotion Race** | `parts/03_dml.sql` (Lines 247–340), `railway_case_study6.sql` (Lines 1592–1670) | Select earliest waitlisted PNR in FIFO order and serialize update with `WHERE pnr = v_promoted AND status = 'WAITLIST'`. | Tested two waitlisted passengers (WL1, WL2). Cancelled confirmed ticket; verified WL1 promoted, WL2 stayed in queue. | WL1 promoted to seat 301; WL2 remained in WAITLIST queue. Second cancel promoted WL2. | **PASS** | None. Promotion strictly respects booking timestamp and PNR order. |
| **D4: Duplicate Seat Script Idempotency** | `parts/02b_seat.sql` | Added `WHERE NOT EXISTS (SELECT 1 FROM seat s WHERE ...)` and `COMMIT;`. | Executed `parts/01_ddl.sql`, `02_data.sql`, and `02b_seat.sql` consecutively in fresh schema. | `02b_seat.sql` inserted 0 rows without throwing `ORA-00001`. Completely idempotent. | **PASS** | None. |
| **D5: Master Modular Runner** | `parts/run_all.sql` | Created runner using relative path execution (`@@`) and `SET DEFINE OFF`. | Executed `@parts/run_all.sql` from repository root in clean schema. | Completed all 5 steps with 0 syntax or file-resolution errors. | **PASS** | None. `@@` resolves relative to script folder. |
| **D6: Stored Procedure Input Validation** | `book_ticket`, `cancel_ticket` | Explicit checks for nonexistent passenger (`-20015`), schedule (`-20014`), PNR (`-20016`). | Passed invalid IDs: passenger 88888, schedule 99999, PNR 9999999999. | Caught exact expected exception codes: `ORA-20015`, `ORA-20014`, `ORA-20016`. | **PASS** | None. |
| **D7: Foreign Key Performance Indexes** | `parts/01_ddl.sql`, `railway_case_study6.sql` | Created 7 B-tree indexes for foreign keys (`RESERVATION`, `ROUTE_STOP`, `TRAIN`, `COACH`). | Queried `USER_INDEXES` and ran `EXPLAIN PLAN` on Query A1. | All 7 indexes created; Optimizer actively selected `IX_RES_FROM_STN` range scan. | **PASS** | None. Eliminates unindexed FK lock contention. |
| **D8: Part 0 Clean-Up Drop Loop** | `parts/01_ddl.sql`, `railway_case_study6.sql` | Added drop loop for stored procedures and functions. | Re-ran Part 0 clean-up block in populated schema. | Procedures and function dropped cleanly without leaving orphan objects. | **PASS** | None. |
| **D9: Zero-Refund Payment Status Accuracy** | `cancel_ticket` | Set `pay_status = 'SUCCESS'` when `v_refund = 0`. | Created test departure in 2 hours (<4h bracket, 0 refund). Cancelled ticket. | `refund_amount = 0`, `pay_status = 'SUCCESS'`. Original collected funds accurately marked retained. | **PASS** | None. |

---

## 3. Clean-Room Initialization Results

Two isolated disposable Oracle schemas were initialized and evaluated:
1. **Schema 1 (`RAILWAY_MODULAR`):** Built exclusively by executing `parts/run_all.sql`.
2. **Schema 2 (`RAILWAY_CONSOLIDATED`):** Built exclusively by executing `railway_case_study6.sql`.

### Object and Compilation Verification
- **Compilation Errors / Warnings:** **Zero.** (`SELECT * FROM user_objects WHERE status != 'VALID'` returned 0 rows in both schemas).
- **Object Counts:**
  - Tables: 14 (12 core entities + 2 risk module tables)
  - Views: 3 (`V_RESERVATION_PERFORMANCE`, `V_TRAIN_UTILIZATION`, `V_TICKET_DETAILS`)
  - Sequences: 3 (`SEQ_PNR`, `SEQ_PAYMENT`, `SEQ_CANCEL`)
  - Procedures: 3 (`BOOK_TICKET`, `CANCEL_TICKET`, `PRC_CAPACITY_RISK_REPORT`)
  - Functions: 1 (`FN_CAPACITY_RISK`)
  - Triggers: 1 (`TRG_RESERVATION_VALIDATE`)
  - Indexes: 34 (32 normal + 2 function-based unique)
- **Constraint Counts:**
  - Check Constraints: 87
  - Primary Keys: 14
  - Foreign Keys: 18
  - Unique Keys: 10

---

## 4. Modular versus Consolidated Script Equivalence

| Table Name | Modular Rows (`RAILWAY_MODULAR`) | Consolidated Rows (`RAILWAY_CONSOLIDATED`) | Discrepancy |
|---|---|---|---|
| `STATION` | 14 | 14 | 0 |
| `ROUTE` | 4 | 4 | 0 |
| `ROUTE_STOP` | 21 | 21 | 0 |
| `TRAIN` | 9 | 9 | 0 |
| `COACH_CLASS` | 6 | 6 | 0 |
| `COACH` | 30 | 30 | 0 |
| `SEAT` | 320 | 320 | 0 |
| `TRAIN_SCHEDULE` | 28 | 28 | 0 |
| `PASSENGER` | 150 | 150 | 0 |
| `RESERVATION` | 777 (768 sample + 9 demo) | 777 (768 sample + 9 demo) | 0 |
| `PAYMENT` | 777 | 777 | 0 |
| `CANCELLATION` | 36 (35 sample + 1 demo) | 36 (35 sample + 1 demo) | 0 |
| `RISK_THRESHOLD` | 5 | 5 | 0 |
| `CAPACITY_RISK_LOG` | 9 | 9 | 0 |

**Conclusion:** Modular and consolidated deployment paths yield 100% identical schemas, constraints, objects, and row populations.

---

## 5. Transaction, Concurrency & Locking Verification

### Booking & Cancellation Protocol Analysis
* **Lock Scope in `book_ticket`:** Exclusive row lock acquired on target `train_schedule` (`WHERE schedule_id = p_schedule FOR UPDATE`). Serializes booking attempts for that specific train journey.
* **Lock Scope in `cancel_ticket`:** Exclusive row lock acquired on target `reservation` (`WHERE pnr = p_pnr FOR UPDATE OF r.status`). Serializes cancellation on that ticket.
* **Deadlock Invariant:** `book_ticket` never requests existing reservation row locks, and `cancel_ticket` never requests `train_schedule` row locks. Because lock acquisition graphs are strictly disjoint, circular waits (deadlocks) between concurrent booking and cancellation transactions cannot occur.
* **Live Two-Session Race Condition Outcome:**
  * Two concurrent threads competed for the last remaining seat (Seat 308 on Journey 196).
  * Session 1 received: `CONFIRMED (Seat 308)`.
  * Session 2 received: `WAITLIST (Seat NULL)`.
  * Database state: exactly 1 confirmed ticket holding seat 308; 0 duplicate seat assignments; 0 ORA errors.

---

## 6. Adversarial Data-Integrity Verification (Direct DML Bypass)

Constructed negative DML statements directly against tables to test whether database integrity relies on stored procedures:

| Adversarial Attack Scenario | Bypass Mechanism | Target Constraint / Object | Observed Database Defense | Verdict |
|---|---|---|---|---|
| Direct insert of CONFIRMED ticket with NULL seat | Raw `INSERT INTO reservation` | `CK_RES_SEAT_STATUS` | Blocked: `ORA-02290` | **DEFENDED** |
| Direct insert of WAITLIST ticket with physical seat | Raw `INSERT INTO reservation` | `CK_RES_SEAT_STATUS` | Blocked: `ORA-02290` | **DEFENDED** |
| Direct double-booking of same seat on same journey | Raw `INSERT INTO reservation` | `UX_RES_SEAT_JOURNEY` | Blocked: `ORA-00001` | **DEFENDED** |
| Direct duplicate active booking for same passenger | Raw `INSERT INTO reservation` | `UX_RES_PASS_JOURNEY` | Blocked: `ORA-00001` | **DEFENDED** |
| Reverse-direction travel (dest before boarding) | Raw `INSERT INTO reservation` | `TRG_RESERVATION_VALIDATE` (R1) | Blocked: `ORA-20002` | **DEFENDED** |
| Seat assignment from foreign train / wrong class | Raw `INSERT INTO reservation` | `TRG_RESERVATION_VALIDATE` (R2) | Blocked: `ORA-20003` | **DEFENDED** |
| Future booking date past journey departure | Raw `INSERT INTO reservation` | `TRG_RESERVATION_VALIDATE` (R3) | Blocked: `ORA-20004` | **DEFENDED** |
| Direct insert of negative ticket fare | Raw `INSERT INTO reservation` | `CK_RES_FARE` | Blocked: `ORA-02290` | **DEFENDED** |
| Deleting passenger with active booking history | Raw `DELETE FROM passenger` | `FK_RES_PASS` | Blocked: `ORA-02292` | **DEFENDED** |
| Inserting stop sequence with nonexistent station | Raw `INSERT INTO route_stop` | `FK_RS_STATION` | Blocked: `ORA-02291` | **DEFENDED** |

**Conclusion:** Core data integrity is enforced by declarative table constraints, function-based unique indexes, and table triggers. No client can corrupt inventory or bypass referential integrity via direct SQL.

---

## 7. Query Correctness and Performance Analysis

### 7.1 Aggregate Multiplier & Join Audit
* **Query Q2 (Station Footfall):** Uses two independent grouped inline views (`b` on `from_station`, `a` on `to_station`) joined to `station`. Avoids Cartesian multiplication of boarding and alighting movements.
* **Query Q4 (Coach Occupancy):** Pre-aggregates journey count per train before joining `coach` and `seat`. Prevents multiplier inflation on coach seat inventory.

### 7.2 Financial & Revenue Semantics
Independent verification revealed two distinct financial views:
* **Recognized Operating Revenue (`v_reservation_performance` & `v_train_utilization`):** **₹481,831.50**. Counts completed/confirmed ticket fares plus retained cancellation charges. Excludes unearned waitlist deposits on upcoming scheduled journeys.
* **Cash Collections in Escrow (Query Q9):** **₹483,246.50**. Measures gross collections less disbursements. Includes ₹1,415.00 in customer payments held for waitlisted tickets on upcoming scheduled journeys (Schedules 103, 109, and 115) that have not yet departed or refunded.
* Both calculations are mathematically verified and consistent with accounting principles.

### 7.3 Performance Index Optimization
* Index range scan verified on `IX_RES_FROM_STN` (`operation_id = 12`) in Query A1 execution plan.
* Cost decreased from full table scan of `RESERVATION` to targeted indexed fetch by rowid (`operation_id = 13`).

---

## 8. Test Suite Quality & Assertion Audit

* **Assertion Audit:** All assertions in `tests/01` through `tests/06` were inspected for broad exception handling. Every negative test explicitly verifies the exact expected Oracle exception code (`SQLCODE = -2290`, `SQLCODE = -1`, `SQLCODE = -20015`, etc.). Unexpected errors or silent failures immediately fail the assertion.
* **Execution Count Breakdown:**
  * Suite 01 (Schema Validation): 35 assertions
  * Suite 02 (Data Invariants): 12 assertions
  * Suite 03 (Booking Workflow): 17 assertions
  * Suite 04 (Cancellation & Refunds): 13 assertions
  * Suite 05 (Concurrency & Locking): 3 assertions
  * Suite 06 (Analytical Views & Risk): 11 assertions
  * Multi-Session Concurrency Test: 1 assertion
  * **Total Assertions Executed & Verified:** **92 Passed / 0 Failed**.

---

## 9. Regressions Discovered and Fixes Applied

* **Regression Check:** Zero regressions discovered during this independent audit.
* **Verification Check:** All fixes applied during initial remediation remain stable, correct, and fully reproducible across clean-room schemas.

---

## 10. Remaining Risks & Disclosures

1. **Segment-Level Inventory Tracking:** The data model reserves seats for the entire train trip. Mid-journey segment-level reuse is explicitly documented as out of scope.
2. **Oracle Engine Specificity:** The schema utilizes Oracle PL/SQL, analytic window functions (`RATIO_TO_REPORT`, `ROLLUP`, `GROUPING`), function-based indexes, and regex check constraints. It requires Oracle Database 19c or later.

---

## 11. Final Git Diff Summary

* **Modified Files (5):**
  * `parts/01_ddl.sql` (+18, -1 lines): Added 7 FK indexes, enhanced Part 0 cleanup drop loop, cleaned trailing comments.
  * `parts/02_data.sql` (+2 lines): Appended trailing `COMMIT;`.
  * `parts/02b_seat.sql` (+15, -1 lines): Added idempotency guard (`WHERE NOT EXISTS`).
  * `parts/03_dml.sql` (+168, -40 lines): Remediated Test 5.5, hardened `book_ticket` and `cancel_ticket`, made Demo 6.3 idempotent.
  * `railway_case_study6.sql` (+189, -40 lines): Synchronized with modular parts.
* **Added Artifacts (6):**
  * Documentation: `AUDIT_REPORT.md`, `CHANGELOG_AUDIT.md`, `DATABASE_DOCUMENTATION.md`, `README.md`, `TEST_PLAN.md`.
  * Master Runner: `parts/run_all.sql`.
  * Automated Test Suite: `tests/` (Suites 01–06, runners, and concurrency driver).

---

## 12. Final Acceptance Verdict

$$\mathbf{PASS\text{ — All applicable criteria independently verified}}$$

The Railway Reservation and Passenger Service Management System database project is correct, concurrency-safe, normalized to BCNF, reproducible from source, documented across all 14 tables, and supported by 92 automated test assertions.
