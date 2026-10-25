# Comprehensive Test Plan: Railway Reservation Management System

**System:** Railway Reservation and Passenger Service Management System (Oracle SQL & PL/SQL)  
**Test Scope:** Schema constraints, business rules (BR1–BR15), stored procedures, concurrency, data invariants, and analytical queries.  
**Execution Environment:** Oracle AI Database 26ai Free / Oracle 23ai Free on `FREEPDB1` via `SQL*Plus` and Python test automation.  

---

## 1. Traceability Matrix: Requirements to Tests

| Req ID | Requirement / Rule Description | Responsible Objects | Test ID | Test Type | Expected Outcome |
|---|---|---|---|---|---|
| **FR1 / BR1** | Unique upper-case station codes | `station.station_code` PK + CHECK | `TC_STATION_01` | Negative | Lowercase or duplicate station code rejected |
| **FR1 / BR2** | Valid route, origin <> dest, stations on route | `route`, `route_stop` | `TC_ROUTE_01` | Negative | Same origin and dest rejected; duplicate stop rejected |
| **FR2 / BR3** | Train runs on exactly one route | `train.route_id` FK | `TC_TRAIN_01` | Negative | Nonexistent route rejected |
| **FR2 / BR4** | Coach label unique per train; valid class | `coach`, `coach_class` | `TC_COACH_01` | Negative | Duplicate coach label on same train rejected |
| **FR3 / BR5** | Train runs at most once per date | `train_schedule(train_no, journey_date)` UNIQUE | `TC_SCHED_01` | Negative | Duplicate train and date combination rejected |
| **FR4 / BR6** | Passenger phone (10-digit Indian mobile) and email format | `passenger.phone`, `passenger.email` CHECK + UNIQUE | `TC_PASS_01` | Negative | Invalid phone format ('12345') or invalid email rejected |
| **FR5 / BR7** | Seat cannot be sold twice on same journey | `ux_res_seat_journey` Unique Index | `TC_SEAT_01` | Negative | Duplicate booking of already occupied seat rejected |
| **FR5 / BR8** | Passenger holds at most 1 active ticket per journey | `ux_res_pass_journey` Unique Index | `TC_BOOK_01` | Negative | Same passenger booking twice on same journey rejected |
| **FR5 / BR9** | CONFIRMED tickets have seat; WAITLIST/CANCELLED do not | `ck_res_seat_status` CHECK | `TC_RES_01` | Negative | CONFIRMED ticket with NULL seat rejected with ORA-02290 |
| **FR5 / BR10** | Boarding station precedes destination on route | `trg_reservation_validate` (R1) | `TC_TRG_01` | Negative | Boarding at or after destination rejected with ORA-20002 |
| **FR5 / BR11** | Allotted seat belongs to train and booked class | `trg_reservation_validate` (R2) | `TC_TRG_02` | Negative | Seat of another train or wrong class rejected with ORA-20003 |
| **FR5 / BR12** | Ticket cannot be booked after journey date | `trg_reservation_validate` (R3) | `TC_TRG_03` | Negative | Booking date > journey date rejected with ORA-20004 |
| **FR6 / BR13** | Automatic fare computation based on distance & class | `trg_reservation_validate` (R4) | `TC_FARE_01` | Positive | NULL fare automatically computed correctly |
| **FR6 / BR14** | Exactly 1 payment per reservation | `payment.pnr` UNIQUE FK | `TC_PAY_01` | Positive & Negative | Payment created on booking; duplicate payment rejected |
| **FR7 / BR15** | Cancellation refund by time window & waitlist promotion | `cancel_ticket` procedure | `TC_CANCEL_01` | Positive & Edge | Correct refund tier applied; FIFO waitlisted passenger promoted |
| **FR7 / BR15** | Prevent double cancellation | `cancel_ticket` procedure | `TC_CANCEL_02` | Negative | Already cancelled ticket cannot be cancelled again |
| **FR7 / BR15** | Prevent cancelling departed train | `cancel_ticket` procedure | `TC_CANCEL_03` | Negative | Past departure cancellation rejected with ORA-20013 |
| **FR5 / CONC** | Concurrent seat allocation race condition safety | `book_ticket` procedure | `TC_CONC_01` | Concurrency | Two concurrent sessions do not crash; both get seats or waitlist |
| **FR7 / CONC** | Concurrent waitlist promotion race condition safety | `cancel_ticket` procedure | `TC_CONC_02` | Concurrency | Concurrent cancellations promote distinct waitlisted passengers |
| **FR9** | Analytical reporting queries (Q1–Q10, A1–A9) | Views & SQL queries | `TC_QUERY_01` | Regression | Result sets verify accuracy against known invariants |
| **FR10** | Train capacity risk classification module | `risk_threshold`, `fn_capacity_risk`, `prc_capacity_risk_report` | `TC_RISK_01` | Functional & What-If | 12639 and 12637 identified as CAPACITY REQUIRED |

---

## 2. Test Execution Architecture

### 2.1 Static & DDL Validation
- Script compilation and dependency order.
- Foreign key constraints, checks, unique indexes, and triggers.
- Object validity in `USER_OBJECTS` (`STATUS = 'VALID'`).

### 2.2 Functional & Business Logic Testing
- Single and multi-passenger booking workflows.
- Auto-calculation of fares for various distance tiers (<50km min cap vs actual km).
- Cancellation refunds across all time brackets (>=48h: 90%, >=24h: 75%, >=4h: 50%, <4h: 0%, WAITLIST: 100%).
- Waitlist automatic promotion and seat assignment.

### 2.3 Negative & Boundary Testing
- Invalid phone, email, train numbers, coach labels, platform numbers.
- Station not on route, reverse direction booking.
- Date boundary: booking on journey date vs after journey date.
- Coach capacity limits: booking past coach capacity transitions to WAITLIST.
- Passenger booking twice on same journey.

### 2.4 Concurrency & Isolation Testing
- Simulated concurrent booking of the final remaining seat.
- Verification that locks (`SELECT ... FOR UPDATE`) or safe retry logic prevent `ORA-00001` crashes.
- Concurrent cancellations promoting distinct waitlisted passengers.

### 2.5 Invariant Checks
- Invariant 1: `COUNT(*) WHERE CONFIRMED AND seat_id IS NULL = 0`
- Invariant 2: `COUNT(*) WHERE CANCELLED AND seat_id IS NOT NULL = 0`
- Invariant 3: `COUNT(*) WHERE WAITLIST AND seat_id IS NOT NULL = 0`
- Invariant 4: No two active tickets share `(schedule_id, seat_id)`.
- Invariant 5: No active ticket has seat from different train.
- Invariant 6: Every reservation has exactly one payment.
- Invariant 7: Payment amounts equal reservation fare.
- Invariant 8: Every cancelled reservation has exactly one cancellation record.
