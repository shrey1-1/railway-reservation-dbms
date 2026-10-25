# Baseline Audit Report: Railway Reservation Management System

**Repository:** `https://github.com/shrey1-1/railway-reservation-dbms`  
**Audit Date:** October 25, 2026  
**Auditor:** Senior Database Engineer, Oracle PL/SQL Specialist, QA & Security Auditor  
**Baseline Commit:** `80ea3f94d106c0b3ec77658e6a01c88567c15f62`  
**Baseline Branch:** `main`  
**Working Tree Status:** Clean  

---

## 1. Executive Summary

A comprehensive baseline audit was conducted on the Railway Reservation and Passenger Service Management System database project (Case Study 6 for BCSE302P Database Systems Lab). The system is implemented for Oracle Database using SQL and PL/SQL.

Testing and verification were performed against a live **Oracle AI Database 26ai Free Release 23.26.0.0.0** instance running locally on Windows with an isolated disposable test schema (`RAILWAY_TEST` in container `FREEPDB1`).

### Summary of Verdict
- **Baseline Quality:** High academic quality; comprehensive schema normalized to BCNF with 12 core tables; function-based unique indexes for seat and passenger journey integrity; advanced analytical queries; and an automated decision-support risk module.
- **Verified Defects Identified:** 9 distinct findings across data integrity, race conditions, test repeatability, modular script execution, missing indexes, and error handling.
- **Remediation Plan:** Apply targeted, non-destructive fixes to modular scripts and consolidated SQL, establish comprehensive automated test suites, verify data invariants and concurrency behavior, and document the complete system architecture.

---

## 2. Environment and Runtime Assumptions

| Component | Baseline Specification | Notes |
|---|---|---|
| **RDBMS** | Oracle Database (tested on Oracle 26ai Free / 23ai Free) | Pluggable Database `FREEPDB1` |
| **Client** | Oracle SQL*Plus Release 23.26.0.0.0 | Running with `SERVEROUTPUT ON` |
| **Language / Automation** | Python 3.13.0 | Custom test drivers and invariant checkers |
| **Test Isolation** | Dedicated user `RAILWAY_TEST` | Disposable schema; safe reset without impacting host |

---

## 3. Repository File Inventory

| Path | Purpose | Dependencies | Execution Order | Findings / Status |
|---|---|---|---|---|
| `railway_case_study6.sql` | Consolidated master script containing Parts 0 through 10 (2,105 lines) | Self-contained; drops and recreates schema | Single-file runner | Verified baseline run; contains Defects D1, D2, D3, D6, D7, D8, D9 |
| `parts/01_ddl.sql` | DDL script: Part 0 (cleanup) and Part 1 (table creation, sequences, trigger) (277 lines) | None | 1 | Dangling header `-- PART 2` at line 276; lacks indexes on several foreign keys |
| `parts/02_data.sql` | Static sample data: Stations, routes, trains, classes, coaches, seats, schedules, passengers, reservations (1,062 lines) | `01_ddl.sql` | 2 | Missing `COMMIT;` at end; already contains complete 320-row seat insertion |
| `parts/02b_seat.sql` | Extracted standalone seat insertion script (18 lines) | `01_ddl.sql`, `coach`, `coach_class` | Optional / standalone | Defect D4: Exact duplicate of lines 98–112 in `02_data.sql`. Fails with 320 `ORA-00001` errors if run in sequence |
| `parts/03_dml.sql` | Part 2 (payments, cancellations), Part 3 (ALTER), Part 4 (DML), Part 5 (tests), Part 6 (procedures & demo) (279 lines) | `01_ddl.sql`, `02_data.sql` | 3 | Defect D1 (Test 5.5 failure on post-Oct 21 dates); Defects D2 & D3 (concurrency in `book_ticket` / `cancel_ticket`) |
| `parts/04_queries.sql` | Part 7 (views), Part 8 (queries Q1–Q10), Part 9 (advanced queries A1–A9), Part 10 (capacity risk module) (486 lines) | `03_dml.sql` | 4 | Creates `risk_threshold` and `capacity_risk_log` tables in query phase; all 19 queries functional |
| `er_diagram.png` | Entity-Relationship diagram (1421x961 PNG, 128 KB) | N/A | Documentation | Identical binary to `word/media/image1.png` embedded in `report.docx` |
| `report.docx` | Academic project report (BCSE302P Case Study 6) (142 KB) | N/A | Documentation | Thorough documentation of FR1–FR10, BR1–BR15, BCNF proofs, queries, screenshots |

---

## 4. Script Consistency and Equivalence Analysis

An automated comparison between `railway_case_study6.sql` and the modular files in `parts/` confirmed:
- `parts/01_ddl.sql` is lines 1 to 277 of `railway_case_study6.sql`.
- `parts/02_data.sql` is lines 278 to 1339 of `railway_case_study6.sql`.
- `parts/03_dml.sql` is lines 1340 to 1618 of `railway_case_study6.sql`.
- `parts/04_queries.sql` is lines 1619 to 2105 of `railway_case_study6.sql`.
- `parts/02b_seat.sql` is an isolated duplicate of lines 98 to 112 in `parts/02_data.sql`.

**Divergence Risk:** There is no automated build/synchronization tool. Any manual edits made to modular scripts will cause divergence from `railway_case_study6.sql` unless systematically synced.

---

## 5. Baseline Execution Results

The baseline script was executed against Oracle 26ai Free (`railway_test` schema). The run executed 2,105 lines with the following outcomes:
- **Clean-up (Part 0):** Successfully dropped existing objects.
- **DDL Creation (Part 1):** 12 tables, 3 sequences, 3 explicit indexes, and 1 trigger created without error.
- **Data Loading (Part 2):** 14 stations, 4 routes, 21 route stops, 9 trains, 6 coach classes, 30 coaches, 320 seats, 27 schedules, 150 passengers, 768 reservations, 768 payments, 35 cancellations loaded successfully.
- **Schema Alteration (Part 3):** 4 `ALTER TABLE` statements succeeded.
- **DML Operations (Part 4):** Age-based concession computation, timetable update, and reservation modification succeeded.
- **Integrity Enforcement (Part 5):**
  - Test 5.1 (invalid phone): Correctly raised `ORA-02290` (`CK_PASS_PHONE`).
  - Test 5.2 (double booking same seat): Correctly raised `ORA-00001` (`UX_RES_SEAT_JOURNEY`).
  - Test 5.3 (seat from another train): Correctly raised `ORA-20003` (Trigger).
  - Test 5.4 (destination before origin): Correctly raised `ORA-20002` (Trigger).
  - **Test 5.5 (confirmed ticket without seat): FAILED with `ORA-20004: Booking date cannot be after the journey date` instead of expected `ORA-02290: check constraint (CK_RES_SEAT_STATUS) violated`.** (Root cause: Date sensitivity).
  - Test 5.6 (delete passenger with bookings): Correctly raised `ORA-02292` (`FK_RES_PASS`).
  - Test 5.7 (unknown station code): Correctly raised `ORA-02291` (`FK_RS_STATION`).
- **Stored Procedures & Demo (Part 6):** `book_ticket` and `cancel_ticket` compiled and executed the 9-passenger booking + cancellation demo cleanly.
- **Views (Part 7):** All 3 views compiled and queried successfully.
- **Queries Q1 to Q10 (Part 8):** All 10 queries executed with valid results.
- **Advanced Queries A1 to A9 (Part 9):** All 9 advanced queries executed with valid results.
- **Capacity Risk Module (Part 10):** Decision-support query, procedure execution, and what-if analysis executed and matched documented outputs.

---

## 6. Detailed Defect Catalog

### Defect D1: Test 5.5 Date Sensitivity Failure
- **Severity:** P1 (High)
- **Status:** Confirmed Defect
- **Location:** `railway_case_study6.sql` (Line 1459), `parts/03_dml.sql` (Line 119)
- **Description:** Test 5.5 attempts to insert a reservation with `status = 'CONFIRMED'` and `seat_id = NULL` on schedule 103 without specifying `booking_date`.
- **Root Cause:** When `booking_date` is omitted, Oracle assigns `DEFAULT TRUNC(SYSDATE)`. Schedule 103 has `journey_date = DATE '2026-10-21'`. On any test date after October 21, 2026, trigger `TRG_RESERVATION_VALIDATE` checks `IF INSERTING AND :NEW.booking_date > v_jdate` and immediately raises `ORA-20004`. The table check constraint `CK_RES_SEAT_STATUS` is never evaluated.
- **Impact:** Test 5.5 fails to verify its stated requirement in academic lab reviews whenever run after October 21, 2026.
- **Remediation:** Explicitly provide a valid `booking_date` (e.g. `DATE '2026-10-20'`) in Test 5.5 so trigger validation succeeds and check constraint `CK_RES_SEAT_STATUS` correctly raises `ORA-02290`.

### Defect D2: Concurrency Race Condition in `book_ticket`
- **Severity:** P1 (High)
- **Status:** Confirmed Defect
- **Location:** `parts/03_dml.sql` (Lines 168–176), `railway_case_study6.sql` (Lines 1507–1515)
- **Description:** `book_ticket` uses `SELECT MIN(st.seat_id) INTO v_seat ... WHERE NOT EXISTS (...)` without locking the candidate seat or serializing the schedule allocation.
- **Root Cause:** Under concurrent execution, two sessions can read the same free seat. Both attempt to insert the same `seat_id` into `reservation`. The second session triggers `ORA-00001: unique constraint (UX_RES_SEAT_JOURNEY) violated` and ungracefully crashes, even if other seats remain free in the coach.
- **Impact:** System fails under concurrent multi-user load.
- **Remediation:** 
  1. Acquire a row lock on the target schedule (`SELECT sched_status INTO v_sched_status FROM train_schedule WHERE schedule_id = p_schedule FOR UPDATE;`).
  2. Implement an allocation retry loop that catches `DUP_VAL_ON_INDEX` and automatically selects the next available seat or transitions to WAITLIST.

### Defect D3: Concurrency Race Condition in `cancel_ticket` Waitlist Promotion
- **Severity:** P1 (High)
- **Status:** Confirmed Defect
- **Location:** `parts/03_dml.sql` (Lines 224–233), `railway_case_study6.sql` (Lines 1563–1572)
- **Description:** When promoting a waitlisted passenger upon cancellation, the subquery `SELECT pnr FROM (SELECT pnr FROM reservation WHERE ... status = 'WAITLIST' ORDER BY booking_date, pnr) WHERE ROWNUM = 1` does not lock the waitlisted row.
- **Root Cause:** If two cancellations for the same train journey occur concurrently, both find the same earliest waitlisted passenger. One promotes the passenger to the first released seat; the other overwrites or conflicts, leaving subsequent waitlisted passengers unpromoted.
- **Impact:** Corrupted seat allocation and loss of FIFO waitlist integrity during concurrent cancellations.
- **Remediation:** Explicitly lock the candidate waitlisted row using `SELECT ... FOR UPDATE` before applying the promotion update.

### Defect D4: Duplicate Conflicting Script `parts/02b_seat.sql`
- **Severity:** P2 (Medium)
- **Status:** Confirmed Defect
- **Location:** `parts/02b_seat.sql`
- **Description:** `02b_seat.sql` contains an exact copy of the seat population query already executed in `02_data.sql` (lines 98–112).
- **Root Cause:** Redundant artifact left in repository without idempotency guards.
- **Impact:** Executing scripts alphabetically or numerically (`01`, `02`, `02b`, `03`) results in 320 fatal `ORA-00001` constraint violation errors.
- **Remediation:** Make `02b_seat.sql` idempotent using `WHERE NOT EXISTS (SELECT 1 FROM seat s WHERE s.seat_id = ...)` and clearly document its role as a standalone/optional seat generator.

### Defect D5: Missing Master Runner Script for Modular Setup
- **Severity:** P2 (Medium)
- **Status:** Confirmed Defect
- **Location:** Repository Root / `parts/`
- **Description:** No automated script exists to run `01_ddl.sql`, `02_data.sql`, `03_dml.sql`, and `04_queries.sql` in sequence.
- **Impact:** High probability of user error and inconsistent setup order during lab evaluations.
- **Remediation:** Provide `parts/run_all.sql` that executes the parts with proper feedback, error handling, and completion confirmation.

### Defect D6: Missing Input Validation and PL/SQL Error Handling
- **Severity:** P2 (Medium)
- **Status:** Confirmed Defect
- **Location:** `book_ticket`, `cancel_ticket`
- **Description:** Procedures do not check whether `p_passenger` exists or if `p_pnr` exists before executing statements, causing raw Oracle exceptions (`NO_DATA_FOUND`, `ORA-02291`) to propagate.
- **Remediation:** Add explicit validation and informative user-facing application errors (`-20014`, `-20015`, `-20016`).

### Defect D7: Missing Foreign Key Indexes
- **Severity:** P2 (Medium)
- **Status:** Confirmed Defect
- **Location:** `01_ddl.sql`, `railway_case_study6.sql`
- **Description:** Foreign key columns `RESERVATION(passenger_id)`, `RESERVATION(from_station)`, `RESERVATION(to_station)`, `ROUTE_STOP(station_code)`, `TRAIN(route_id)`, `COACH(class_code)` lack supporting indexes.
- **Impact:** Table locks during unindexed foreign key updates/deletes and full table scans on large join queries.
- **Remediation:** Create targeted non-unique B-tree indexes for all unindexed foreign key columns.

### Defect D8: Incomplete Object Drop in Clean-up Block
- **Severity:** P3 (Low)
- **Status:** Probable Risk
- **Location:** Part 0 in `01_ddl.sql` and `railway_case_study6.sql`
- **Description:** Part 0 explicitly drops views, tables, and sequences, but does not explicitly drop procedures `book_ticket`, `cancel_ticket`, `prc_capacity_risk_report` or function `fn_capacity_risk`.
- **Remediation:** Include procedures and functions in the Part 0 drop loop.

### Defect D9: Inaccurate Payment Status for Zero-Refund Cancellations
- **Severity:** P3 (Low)
- **Status:** Confirmed Defect
- **Location:** `cancel_ticket` procedure
- **Description:** When a ticket is cancelled within 4 hours of departure (`v_refund = 0`), `pay_status` is updated to `'PARTIAL_REFUND'` instead of indicating no refund was given.
- **Remediation:** Update `pay_status` to `'PARTIAL_REFUND'` only when `v_refund > 0`.

---

## 7. Data Quality and Invariant Verification (Baseline)

An automated invariant check was executed against all 768 sample reservations and 320 seats. Results:
- Orphaned seats: **0**
- Orphaned coaches: **0**
- Duplicate active seat assignments on same schedule: **0**
- Duplicate active passengers on same schedule: **0**
- Seats assigned to wrong train: **0**
- Seats assigned to wrong class: **0**
- Reservations with invalid station stop sequence: **0**
- Reservations with fare mismatch against formula: **0**
- Reservations without payment: **0**
- Payments with amount mismatch against fare: **0**
- Cancelled reservations without cancellation record: **0**
- Non-cancelled reservations with cancellation record: **0**

Baseline data quality is exceptionally high and complies with all defined integrity rules.

---

## 8. Baseline Audit Sign-off

- **Baseline Code State:** Intact, documented, and fully understood.
- **Remediation Authorization:** Proceed to remediation in order of priority (P1 -> P2 -> P3), followed by comprehensive regression testing.
