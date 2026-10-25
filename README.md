# Railway Reservation and Passenger Service Management System
## BCSE302P — Database Systems Lab (Case Study 6)

[![Database: Oracle](https://img.shields.io/badge/Oracle-23ai%20%7C%2026ai-red.svg)](https://www.oracle.com/database/)
[![Status: Audited & Verified](https://img.shields.io/badge/Status-Audited%20%26%20Verified-brightgreen.svg)]()
[![Tests: 92 Passed](https://img.shields.io/badge/Tests-92%20Passed-success.svg)]()

A relational database project for Oracle Database implementing a complete Railway Reservation and Passenger Service Management System. The project models railway network infrastructure, physical coach/seat layouts, dated train runs, ticketing transactions, fare calculations, and train capacity risk classification.

---

## Key Features

1. **Normalized Relational Model (12 Core BCNF Tables):**
   - Stations, corridors/routes, and sequenced route stops.
   - Trains, coach classes, coaches, and seats/berths.
   - Dated train schedules, registered passengers, reservations, payments, and cancellations.
2. **Database-Level Seat Allocation Integrity:**
   - Function-based unique index `ux_res_seat_journey` guarantees no seat is double-booked on the same train journey.
   - Table check constraint `ck_res_seat_status` guarantees that confirmed tickets hold seats, while waitlist/cancelled tickets cannot hold seats.
3. **Automated Business Rules via Multi-Table Trigger:**
   - Route direction validation (boarding station must precede destination).
   - Seat assignment validation (seat must belong to a coach attached to the train and requested class).
   - Dynamic fare computation (`GREATEST(distance, 50) * rate + reservation_fee`).
4. **Automated Booking & Cancellation Stored Procedures:**
   - `book_ticket`: Allocates available seat or places passenger on waitlist; enforces 1 active booking per journey rule; concurrency-hardened with row locking and bounded retry loop.
   - `cancel_ticket`: Calculates graduated refund based on time remaining to departure; immediately promotes earliest waitlisted passenger in FIFO order.
5. **Train Capacity Risk Identification Module (BTL-6):**
   - Analytical views (`v_reservation_performance`, `v_train_utilization`, `v_ticket_details`).
   - Automated decision-support module classifying trains into `CAPACITY REQUIRED`, `HIGH DEMAND`, and `NORMAL`.

---

## Repository Structure

```
├── AUDIT_REPORT.md             # Baseline audit findings, defects, and root-cause analysis
├── CHANGELOG_AUDIT.md          # Remediation changelog and verification record
├── DATABASE_DOCUMENTATION.md   # Data dictionary, ER relationships, and API documentation
├── TEST_PLAN.md                # Traceability matrix and test specifications
├── er_diagram.png              # Entity-Relationship diagram
├── report.docx                 # Academic lab report
├── railway_case_study6.sql     # Consolidated single-file script (Parts 0 through 10)
├── parts/                      # Modular script suite
│   ├── run_all.sql             # Master modular runner
│   ├── 01_ddl.sql              # Schema, constraints, sequences, indexes, triggers
│   ├── 02_data.sql             # Reference and operational sample data
│   ├── 02b_seat.sql            # Idempotent standalone seat generator
│   ├── 03_dml.sql              # ALTER, DML, integrity tests, stored procedures
│   └── 04_queries.sql          # Views, queries Q1-Q10, advanced A1-A9, risk module
└── tests/                      # Automated test suite
    ├── 01_schema_validation.sql
    ├── 02_data_invariants.sql
    ├── 03_booking_workflow_test.sql
    ├── 04_cancellation_refund_test.sql
    ├── 05_concurrency_test.sql
    ├── 06_queries_verification.sql
    ├── run_all_tests.sql       # Master test runner in SQL*Plus
    ├── run_tests.py            # Automated Python test runner
    └── test_concurrency_race.py# Live multi-threaded concurrency race test
```

---

## Quick Start & Setup

### 1. Prerequisites
- Oracle Database (tested on Oracle 23ai / 26ai Free).
- SQL*Plus client.
- Python 3.10+ (for automated test runners).

### 2. Execution Options

#### Option A: Run Consolidated Script (Single File)
In SQL*Plus:
```sql
@railway_case_study6.sql
```

#### Option B: Run Modular Scripts in Sequence
In SQL*Plus:
```sql
@parts/run_all.sql
```

---

## Running Automated Tests

### 1. Complete Test Suite via Python
```bash
python tests/run_tests.py
```
Output:
```
  * TEST SUITE 01 (SCHEMA VALIDATION): ALL CHECKS PASSED
  * TEST SUITE 02 (DATA INVARIANTS): ALL 12 CHECKS PASSED
  * TEST SUITE 03 (BOOKING WORKFLOW): ALL CHECKS PASSED
  * TEST SUITE 04 (CANCELLATION & REFUNDS): ALL CHECKS PASSED
  * TEST SUITE 05 (CONCURRENCY & LOCKING): ALL CHECKS PASSED
  * TEST SUITE 06 (ANALYTICAL VIEWS & RISK): ALL CHECKS PASSED

Total Assertions Passed: 91
Total Assertions Failed: 0
[OK] All test suites passed successfully with zero defects.
```

### 2. Live Multi-Session Concurrency Race Test
Verifies that two simultaneous sessions competing for the last available seat do not deadlock or raise constraint errors:
```bash
python tests/test_concurrency_race.py
```
Output:
```
Session 1 output: RESULT:4200001093:CONFIRMED
Session 2 output: RESULT:4200001094:WAITLIST
[PASS] Concurrency integrity verified: 1 passenger confirmed, 1 waitlisted, 0 seat collisions.
```

### 3. Running SQL Test Suites Directly in SQL*Plus
```sql
@tests/run_all_tests.sql
```
