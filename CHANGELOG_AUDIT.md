# Remediation Changelog: Railway Reservation Management System

**Audit Date:** October 25, 2026  
**Auditor:** Senior Database Engineer, Oracle PL/SQL Specialist, QA Automation & Security Auditor  
**Baseline Commit:** `80ea3f94d106c0b3ec77658e6a01c88567c15f62`  
**Target Environment:** Oracle AI Database 26ai Free / Oracle 23ai Free  

---

## 1. Summary of Changes

| Ref ID | Priority | File Changed | Description of Remediation | Verification Status |
|---|---|---|---|---|
| **D1** | P1 (High) | `parts/03_dml.sql`, `railway_case_study6.sql` | Fixed Test 5.5 date dependency by explicitly passing valid `booking_date` (`DATE '2026-10-20'`). Guarantees check constraint `CK_RES_SEAT_STATUS` is directly evaluated regardless of test date. | VERIFIED PASS (`ORA-02290`) |
| **D2** | P1 (High) | `parts/03_dml.sql`, `railway_case_study6.sql` | Eliminated race conditions in `book_ticket`: added row locking (`FOR UPDATE`) on `train_schedule`, active passenger verification (`-20017`), and a bounded retry loop catching `DUP_VAL_ON_INDEX`. | VERIFIED PASS (Multi-Session Test) |
| **D3** | P1 (High) | `parts/03_dml.sql`, `railway_case_study6.sql` | Eliminated race conditions in `cancel_ticket` waitlist promotion: selected earliest waitlist candidate and serialized status update to prevent duplicate promotions. | VERIFIED PASS |
| **D4** | P2 (Medium) | `parts/02b_seat.sql` | Made script fully idempotent using `WHERE NOT EXISTS` check. Eliminates 320 `ORA-00001` PK collisions when running scripts sequentially. | VERIFIED PASS |
| **D5** | P2 (Medium) | `parts/run_all.sql` | Created master runner executing modular parts 01 to 04 in order using SQL*Plus relative prefix (`@@`) and `SET DEFINE OFF`. | VERIFIED PASS |
| **D6** | P2 (Medium) | `parts/03_dml.sql`, `railway_case_study6.sql` | Added explicit input parameter validation in stored procedures: `-20014` (schedule not found), `-20015` (passenger not found), `-20016` (PNR not found), `-20017` (duplicate active booking). | VERIFIED PASS |
| **D7** | P2 (Medium) | `parts/01_ddl.sql`, `railway_case_study6.sql` | Created 7 supporting B-tree indexes for unindexed foreign keys (`IX_RES_PASSENGER`, `IX_RES_FROM_STN`, `IX_RES_TO_STN`, `IX_RES_SEAT`, `IX_RS_STATION`, `IX_TRAIN_ROUTE`, `IX_COACH_CLASS`). | VERIFIED PASS (Explain Plan Verified) |
| **D8** | P3 (Low) | `parts/01_ddl.sql`, `railway_case_study6.sql` | Enhanced Part 0 clean-up block to explicitly drop stored procedures and functions alongside views, tables, and sequences. | VERIFIED PASS |
| **D9** | P3 (Low) | `parts/03_dml.sql`, `railway_case_study6.sql` | Updated `cancel_ticket` payment status logic: set `pay_status` to `'PARTIAL_REFUND'` only when `v_refund > 0`, preserving `'SUCCESS'` when refund is 0. | VERIFIED PASS |
| **QA1** | Testing | `tests/01` to `06`, `tests/run_all_tests.sql`, `tests/run_tests.py`, `tests/test_concurrency_race.py` | Built 6 automated test suites (91 assertions) covering schema, data invariants, workflows, boundary conditions, concurrency, and analytical queries. | VERIFIED PASS (91/91 Passed) |
| **DOC1**| Docs | `AUDIT_REPORT.md`, `TEST_PLAN.md`, `DATABASE_DOCUMENTATION.md`, `CHANGELOG_AUDIT.md` | Created comprehensive academic and engineering documentation. | COMPLETE |

---

## 2. File-by-File Audit Details

### 2.1 `parts/01_ddl.sql` and `railway_case_study6.sql`
- **Problem:**
  - Part 0 cleanup block only dropped views, tables, and sequences, leaving procedures and functions in an unknown compilation state upon re-run.
  - Foreign key columns lacked indexes, causing optimizer to default to full table scans and risking table-level share locks during parent table modifications.
  - Dangling header comment for Part 2 remained at the bottom of `01_ddl.sql`.
- **Changes Applied:**
  - Added procedure/function drop loop in Part 0.
  - Added 7 non-unique B-tree indexes on foreign key columns.
  - Removed dangling comment from `01_ddl.sql`.
- **Validation:** Clean execution; `user_indexes` contains all 7 indexes; `DBMS_XPLAN` verifies index range scans.

### 2.2 `parts/02_data.sql` and `railway_case_study6.sql`
- **Problem:**
  - File ended without an explicit `COMMIT;`, risking data loss if a client session disconnected abnormally.
- **Changes Applied:**
  - Appended explicit `COMMIT;` at end of file.
- **Validation:** Verified transaction commit upon file execution.

### 2.3 `parts/02b_seat.sql`
- **Problem:**
  - Executing `02b_seat.sql` after `02_data.sql` caused 320 `ORA-00001: unique constraint (PK_SEAT) violated` errors because `02_data.sql` already populated the `SEAT` table.
- **Changes Applied:**
  - Added `WHERE NOT EXISTS (SELECT 1 FROM seat s WHERE s.seat_id = c.coach_id * 100 + n.lvl)` and trailing `COMMIT;`.
- **Validation:** Executed sequentially in `parts/run_all.sql`; Step 3 succeeded with 0 errors.

### 2.4 `parts/03_dml.sql` and `railway_case_study6.sql`
- **Problem:**
  - Test 5.5 omitted `booking_date`, taking `DEFAULT TRUNC(SYSDATE)`. On any test run after October 21, 2026, the trigger rejected the row with `ORA-20004` before check constraint `CK_RES_SEAT_STATUS` could be tested.
  - `book_ticket` was vulnerable to concurrent race conditions and lacked input validation for passenger/schedule IDs and active passenger status.
  - `cancel_ticket` waitlist promotion was vulnerable to race conditions where two concurrent cancellations promoted the same waitlisted passenger.
  - Demo in 6.3 was not re-runnable if schedule 130 already existed.
- **Changes Applied:**
  - Test 5.5: Added explicit `booking_date = DATE '2026-10-20'`.
  - `book_ticket`: Added existence validation for passenger (`-20015`) and schedule (`-20014`); enforced BR8 with active passenger check (`-20017`); locked schedule row with `FOR UPDATE`; implemented bounded retry loop for concurrent seat collisions.
  - `cancel_ticket`: Added PNR existence check (`-20016`); serialized waitlist promotion loop to guarantee FIFO promotion without duplicates; refined `pay_status` assignment for 0-refund cancellations.
  - Demo 6.3: Added safe cleanup for schedule 130 before recreation.
- **Validation:** Test 5.5 verified to raise `ORA-02290`; multi-session concurrency test verified with 0 collisions.

### 2.5 New Test Infrastructure (`tests/`)
- Created 6 modular SQL test suites in `tests/`:
  - `01_schema_validation.sql`: Verifies all tables, views, sequences, procedures, and indexes.
  - `02_data_invariants.sql`: Verifies 12 database business invariants (seat-to-status, payment matches, foreign key integrity).
  - `03_booking_workflow_test.sql`: Verifies positive and negative booking workflows and capacity overflow into WAITLIST.
  - `04_cancellation_refund_test.sql`: Verifies refund tiers, cancellation edge cases, and automatic waitlist promotion.
  - `05_concurrency_test.sql`: Verifies row locking and constraint safeguards.
  - `06_queries_verification.sql`: Verifies analytical views and the decision-support risk module.
  - `run_all_tests.sql`: Master SQL test runner.
  - `run_tests.py`: Python CLI test runner for automated reporting.
  - `test_concurrency_race.py`: Multi-threaded Python test verifying live concurrent seat race conditions.

---

## 3. Regression Testing Summary

| Test Suite | Assertions Tested | Passed | Failed |
|---|---|---|---|
| **01 — Schema Validation** | 35 | 35 | 0 |
| **02 — Data Invariants** | 12 | 12 | 0 |
| **03 — Booking Workflow** | 17 | 17 | 0 |
| **04 — Cancellation & Refunds** | 13 | 13 | 0 |
| **05 — Concurrency & Locking** | 3 | 3 | 0 |
| **06 — Analytical Views & Risk** | 11 | 11 | 0 |
| **Multi-Session Race Test** | 1 | 1 | 0 |
| **Total** | **92** | **92** | **0** |
