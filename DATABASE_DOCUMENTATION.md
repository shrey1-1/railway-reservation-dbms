# Database Documentation: Railway Reservation Management System

**Course:** BCSE302P — Database Systems Lab  
**Case Study:** 06 — Railway Reservation and Passenger Service Management System  
**DBMS Engine:** Oracle Database (tested on Oracle AI Database 26ai Free / 23ai Free)  
**Schema Model:** 14 Tables (12 Core BCNF Entities + 2 Decision-Support Tables), 3 Views, 3 Sequences, 1 Validation Trigger, 3 Stored Procedures, 1 Classification Function.  

---

## 1. System Overview & Architecture

The Railway Reservation and Passenger Service Management System replaces error-prone spreadsheet-based railway records with a mathematically rigorous, fully normalized relational database. The system models railway network infrastructure (stations, corridors, routes, stops, trains), physical train configurations (coaches, classes, seats/berths), operational schedules (dated train journeys), passenger bookings, payments, and cancellations.

On top of transaction processing, the database features:
1. **Database-Level Seat Allocation Integrity:** Function-based unique indexes enforce that no seat is sold twice per journey and that waitlisted/cancelled tickets cannot hold physical seats.
2. **Automated Fare Calculation:** A multi-table before-insert trigger calculates journey distance and applies class rates and reservation fees automatically.
3. **Automated Booking & FIFO Waitlist Promotion:** Stored procedures manage seat assignment, payment creation, cancellation refunds, and immediate reallocation of released seats to waitlisted passengers.
4. **Train Capacity Risk Identification Module (BTL-6):** Analytical queries, partitioning window functions, and a parameter-driven decision-support module classify trains into `CAPACITY REQUIRED`, `HIGH DEMAND`, and `NORMAL` to advise management on attaching coaches or scheduling special trains.

---

## 2. Entity-Relationship & Relational Architecture

```
  +---------+           1:N           +------------+
  | STATION |------------------------<| ROUTE_STOP |
  +---------+                         +------------+
     |   |                                  |
 1:N |   | 1:N                              | N:1
     v   v                                  v
+-------------+         1:N           +------------+
|    ROUTE    |----------------------<|   TRAIN    |
+-------------+                       +------------+
                                            |
                         +------------------+------------------+
                     1:N |                                 1:N |
                         v                                     v
                   +-----------+                         +----------------+
                   |   COACH   |                         | TRAIN_SCHEDULE |
                   +-----------+                         +----------------+
                         | 1:N                                 | 1:N
                         v                                     v
                   +-----------+                         +----------------+
                   |   SEAT    |                         |  RESERVATION   |
                   +-----------+                         +----------------+
                         |                                  |   ^   ^
                    0..1 |                                  |   |   |
                         +----------------------------------+   |   |
                                                                |   | 1:N
                                                     1:1 +------+   +-------+
                                                         |                  |
                                                         v                  |
                                                   +-----------+     +-------------+
                                                   |  PAYMENT  |     |  PASSENGER  |
                                                   +-----------+     +-------------+
                                                         | 1:0..1
                                                         v
                                                   +--------------+
                                                   | CANCELLATION |
                                                   +--------------+
```

### Relational Schema Representation
- `STATION(station_code, station_name, city, state, rail_zone, platforms)`
- `ROUTE(route_id, route_name, origin_code -> STATION, dest_code -> STATION, distance_km)`
- `ROUTE_STOP(route_id -> ROUTE, stop_seq, station_code -> STATION, km_from_origin)`
- `TRAIN(train_no, train_name, train_type, route_id -> ROUTE, dep_time, run_days, is_active)`
- `COACH_CLASS(class_code, class_name, seats_per_coach, fare_per_km, reservation_fee)`
- `COACH(coach_id, train_no -> TRAIN, coach_label, class_code -> COACH_CLASS)`
- `SEAT(seat_id, coach_id -> COACH, seat_no, berth_type)`
- `TRAIN_SCHEDULE(schedule_id, train_no -> TRAIN, journey_date, sched_status)`
- `PASSENGER(passenger_id, full_name, gender, dob, phone, email, home_city, registered_on, concession_type)`
- `RESERVATION(pnr, passenger_id -> PASSENGER, schedule_id -> TRAIN_SCHEDULE, class_code -> COACH_CLASS, seat_id -> SEAT, from_station -> STATION, to_station -> STATION, booking_date, fare, status)`
- `PAYMENT(payment_id, pnr -> RESERVATION [UQ], amount, pay_mode, paid_on, pay_status)`
- `CANCELLATION(cancel_id, pnr -> RESERVATION [UQ], cancelled_on, refund_amount, reason)`
- `RISK_THRESHOLD(param_code, param_value, description)`
- `CAPACITY_RISK_LOG(run_date, train_no -> TRAIN, occupancy_pct, cancellation_rate, demand_pct, risk_status)`

---

## 3. Data Dictionary

### 3.1 STATION
| Column | Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `station_code` | VARCHAR2(5) | No | — | `pk_station` (PK), `ck_station_code` (UPPER) | Unique 3-5 character station code (e.g. 'MAS', 'SBC') |
| `station_name` | VARCHAR2(80) | No | — | — | Full official name of the railway station |
| `city` | VARCHAR2(40) | No | — | — | Metropolitan city or district |
| `state` | VARCHAR2(30) | No | — | — | State / Union territory |
| `rail_zone` | VARCHAR2(5) | No | — | — | Zonal railway code (e.g. 'SR', 'SWR') |
| `platforms` | NUMBER(2) | No | 1 | `ck_station_pf` (BETWEEN 1 AND 30) | Number of operational platforms |

### 3.2 ROUTE
| Column | Data Type | Nullable | Constraints | Description |
|---|---|---|---|---|
| `route_id` | NUMBER(4) | No | `pk_route` (PK) | Unique route identifier |
| `route_name` | VARCHAR2(60) | No | `uq_route_name` (UQ) | Descriptive corridor name (e.g. 'Chennai-Bengaluru') |
| `origin_code` | VARCHAR2(5) | No | `fk_route_origin` -> `station` | Origin terminus station |
| `dest_code` | VARCHAR2(5) | No | `fk_route_dest` -> `station` | Destination terminus station (`ck_route_ends`: origin <> dest) |
| `distance_km` | NUMBER(5) | No | `ck_route_km` (> 0) | Total track distance in kilometres |

### 3.3 ROUTE_STOP
| Column | Data Type | Nullable | Constraints | Description |
|---|---|---|---|---|
| `route_id` | NUMBER(4) | No | `pk_route_stop` (PK composite), `fk_rs_route` ON DELETE CASCADE | Associated route ID |
| `stop_seq` | NUMBER(2) | No | `pk_route_stop` (PK composite), `ck_rs_seq` (>= 1) | 1-based chronological sequence of stops |
| `station_code` | VARCHAR2(5) | No | `fk_rs_station` -> `station`, `uq_rs_station` (UQ with route_id) | Station served at this stop |
| `km_from_origin` | NUMBER(5) | No | `ck_rs_km` (>= 0) | Cumulative track distance from route origin (0 at origin) |

### 3.4 TRAIN
| Column | Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `train_no` | NUMBER(5) | No | — | `pk_train` (PK), `ck_train_no` (10000–99999) | 5-digit Indian Railways train number |
| `train_name` | VARCHAR2(50) | No | — | `uq_train_name` (UQ) | Commercial train name |
| `train_type` | VARCHAR2(15) | No | — | `ck_train_type` (SUPERFAST, EXPRESS, SHATABDI, VANDE_BHARAT, MAIL) | Service classification |
| `route_id` | NUMBER(4) | No | — | `fk_train_route` -> `route` | Route corridor operated |
| `dep_time` | VARCHAR2(5) | No | — | `ck_train_dep` (Regex HH24:MI) | Origin scheduled departure time |
| `run_days` | VARCHAR2(20) | No | 'DAILY' | `ck_train_days` (Regex 'DAILY' or comma-separated 1-7) | Operating days of week |
| `is_active` | CHAR(1) | No | 'Y' | `ck_train_act` ('Y','N') | Operational status flag |

### 3.5 COACH_CLASS
| Column | Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `class_code` | VARCHAR2(3) | No | — | `pk_coach_class` (PK) | Class code (1A, 2A, 3A, SL, CC, EC) |
| `class_name` | VARCHAR2(30) | No | — | — | Descriptive class title (e.g. 'AC Chair Car') |
| `seats_per_coach` | NUMBER(3) | No | — | `ck_cc_seats` (4–120) | Scaled seat capacity per coach |
| `fare_per_km` | NUMBER(5,2) | No | — | `ck_cc_fare` (> 0) | Base tariff per kilometre |
| `reservation_fee` | NUMBER(5,2) | No | 0 | `ck_cc_fee` (>= 0) | Mandatory supplementary booking fee |

### 3.6 COACH
| Column | Data Type | Nullable | Constraints | Description |
|---|---|---|---|---|
| `coach_id` | NUMBER(5) | No | `pk_coach` (PK) | System surrogate key for coach instance |
| `train_no` | NUMBER(5) | No | `fk_coach_train` -> `train` ON DELETE CASCADE | Train composition assignment |
| `coach_label` | VARCHAR2(4) | No | `uq_coach_train_label` (UQ with train_no) | Physical coach code (e.g. 'C1', 'S1', 'E1') |
| `class_code` | VARCHAR2(3) | No | `fk_coach_class` -> `coach_class` | Travel class of the coach |

### 3.7 SEAT
| Column | Data Type | Nullable | Constraints | Description |
|---|---|---|---|---|
| `seat_id` | NUMBER(7) | No | `pk_seat` (PK) | Surrogate key (`coach_id * 100 + seat_no`) |
| `coach_id` | NUMBER(5) | No | `fk_seat_coach` -> `coach` ON DELETE CASCADE | Coach containing this seat |
| `seat_no` | NUMBER(3) | No | `ck_seat_no` (>= 1), `uq_seat_coach_no` (UQ with coach_id) | Physical seat/berth number |
| `berth_type` | VARCHAR2(12) | No | `ck_seat_berth` (LOWER, MIDDLE, UPPER, SIDE LOWER, SIDE UPPER, WINDOW, AISLE, MIDDLE SEAT) | Physical berth location |

### 3.8 TRAIN_SCHEDULE
| Column | Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `schedule_id` | NUMBER(6) | No | — | `pk_train_schedule` (PK) | Unique train journey run instance |
| `train_no` | NUMBER(5) | No | — | `fk_sched_train` -> `train`, `uq_sched_train_date` (UQ with journey_date) | Train operating the run |
| `journey_date` | DATE | No | — | `uq_sched_train_date` | Date of operation |
| `sched_status` | VARCHAR2(10) | No | 'SCHEDULED' | `ck_sched_status` (SCHEDULED, COMPLETED, CANCELLED, DELAYED) | Operational status |

### 3.9 PASSENGER
| Column | Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `passenger_id` | NUMBER(6) | No | — | `pk_passenger` (PK) | Unique passenger ID |
| `full_name` | VARCHAR2(60) | No | — | — | Passenger legal name |
| `gender` | CHAR(1) | No | — | `ck_pass_gender` ('M','F','T') | Gender |
| `dob` | DATE | No | — | — | Date of birth (used for concession derivation) |
| `phone` | VARCHAR2(10) | No | — | `uq_pass_phone` (UQ), `ck_pass_phone` (Regex Indian 10-digit mobile) | Primary contact number |
| `email` | VARCHAR2(60) | Yes | — | `uq_pass_email` (UQ), `ck_pass_email` (Regex standard email) | Email address |
| `home_city` | VARCHAR2(40) | Yes | — | — | Residential city |
| `registered_on` | DATE | No | SYSDATE | — | Account creation timestamp |
| `concession_type`| VARCHAR2(10) | No | 'NONE' | `ck_pass_concession` (NONE, SENIOR, STUDENT, DIVYANG, DEFENCE) | Concession category |

### 3.10 RESERVATION
| Column | Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `pnr` | NUMBER(10) | No | — | `pk_reservation` (PK) | Passenger Name Record (Ticket ID) |
| `passenger_id` | NUMBER(6) | No | — | `fk_res_pass` -> `passenger` | Booked passenger |
| `schedule_id` | NUMBER(6) | No | — | `fk_res_sched` -> `train_schedule` | Scheduled train run |
| `class_code` | VARCHAR2(3) | No | — | `fk_res_class` -> `coach_class` | Booked class |
| `seat_id` | NUMBER(7) | Yes | — | `fk_res_seat` -> `seat` | Allocated seat (NULL for WAITLIST and CANCELLED) |
| `from_station` | VARCHAR2(5) | No | — | `fk_res_from` -> `station` | Boarding station |
| `to_station` | VARCHAR2(5) | No | — | `fk_res_to` -> `station`, `ck_res_stations` (from <> to) | Alighting destination station |
| `booking_date` | DATE | No | TRUNC(SYSDATE) | — | Date ticket booked |
| `fare` | NUMBER(8,2) | Yes | — | `ck_res_fare` (> 0) | Computed fare at booking time |
| `status` | VARCHAR2(10) | No | 'CONFIRMED' | `ck_res_status` (CONFIRMED, WAITLIST, CANCELLED, COMPLETED) | Ticket status |
| *Table Checks* | — | — | — | `ck_res_seat_status`: (CONFIRMED/COMPLETED with seat) OR (WAITLIST/CANCELLED with NULL seat) | Enforces seat-to-status integrity |
| *Indexes* | — | — | — | `ux_res_seat_journey`: Unique (schedule_id, seat_id) when seat_id NOT NULL<br>`ux_res_pass_journey`: Unique (passenger_id, schedule_id) when status <> 'CANCELLED' | Concurrency & double-booking safeguards |

### 3.11 PAYMENT
| Column | Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `payment_id` | NUMBER(8) | No | — | `pk_payment` (PK) | Unique payment transaction ID |
| `pnr` | NUMBER(10) | No | — | `uq_pay_pnr` (UQ), `fk_pay_res` -> `reservation` ON DELETE CASCADE | Associated reservation (1:1) |
| `amount` | NUMBER(8,2) | No | — | `ck_pay_amt` (> 0) | Monetary transaction amount |
| `pay_mode` | VARCHAR2(10) | No | — | `ck_pay_mode` (UPI, CARD, NETBANKING, WALLET, CASH) | Payment channel |
| `paid_on` | DATE | No | — | — | Payment settlement date |
| `pay_status` | VARCHAR2(14) | No | 'SUCCESS' | `ck_pay_status` (SUCCESS, REFUNDED, PARTIAL_REFUND) | Settlement status |

### 3.12 CANCELLATION
| Column | Data Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `cancel_id` | NUMBER(8) | No | — | `pk_cancellation` (PK) | Unique cancellation reference ID |
| `pnr` | NUMBER(10) | No | — | `uq_cancel_pnr` (UQ), `fk_cancel_res` -> `reservation` ON DELETE CASCADE | Cancelled reservation (1:0..1) |
| `cancelled_on` | DATE | No | — | — | Cancellation date |
| `refund_amount`| NUMBER(8,2) | No | 0 | `ck_cancel_refund` (>= 0) | Monetary refund granted |
| `reason` | VARCHAR2(60) | Yes | — | — | Cancellation reason category |

---

## 4. Business Rules & Enforcement Mechanics

| Rule ID | Statement | Enforced By |
|---|---|---|
| **BR1** | Station codes are unique uppercase identifiers (3–5 characters). | `station.station_code` PRIMARY KEY + `ck_station_code` CHECK. |
| **BR2** | Origin and destination must differ; no station may appear twice on a single route. | `ck_route_ends` CHECK, `uq_rs_station` UNIQUE composite key. |
| **BR3** | Every train operates on exactly one corridor route. | `train.route_id` NOT NULL FOREIGN KEY. |
| **BR4** | Coach labels are unique within a train; coach belongs to one class. | `uq_coach_train_label` UNIQUE composite key + `fk_coach_class` FK. |
| **BR5** | A train service operates at most once per calendar date. | `uq_sched_train_date` UNIQUE composite key on `(train_no, journey_date)`. |
| **BR6** | Passenger phone must be a 10-digit Indian mobile number; phone and email are unique. | `ck_pass_phone` REGEXP CHECK, `ck_pass_email` REGEXP CHECK, UNIQUE constraints. |
| **BR7** | A physical seat cannot be sold twice on the same train journey. | Function-based UNIQUE index `ux_res_seat_journey` on `(schedule_id, seat_id)`. |
| **BR8** | A passenger cannot hold multiple active tickets for the same journey run. | Function-based UNIQUE index `ux_res_pass_journey` on `(passenger_id, schedule_id)` when status <> 'CANCELLED'. |
| **BR9** | CONFIRMED/COMPLETED tickets must hold a seat; WAITLIST/CANCELLED must have NULL seat. | Table-level check constraint `ck_res_seat_status`. |
| **BR10** | Boarding station must strictly precede the destination in route stop sequence. | Trigger `trg_reservation_validate` (Rule R1, error `-20002`). |
| **BR11** | Allocated seat must belong to a coach attached to the journey's train and booked class. | Trigger `trg_reservation_validate` (Rule R2, error `-20003`). |
| **BR12** | Booking date cannot be in the future relative to the journey departure date. | Trigger `trg_reservation_validate` (Rule R3, error `-20004`). |
| **BR13** | Fare is computed as `ROUND(MAX(distance_km, 50) * fare_per_km + reservation_fee)`. | Trigger `trg_reservation_validate` (Rule R4, auto-calculated when fare IS NULL). |
| **BR14** | Every reservation requires exactly one payment; at most one cancellation. | UNIQUE foreign keys in `payment.pnr` and `cancellation.pnr`. |
| **BR15** | Refund tiers based on hours before departure; FIFO promotion of earliest waitlist. | Stored procedure `cancel_ticket` (`>=48h`: 90%, `>=24h`: 75%, `>=4h`: 50%, `<4h`: 0%, WAITLIST: 100%). |
| **BR16** | Passengers with historical bookings cannot be deleted (child records exist). | RESTRICT foreign key `fk_res_pass` on `reservation`. |

---

## 5. PL/SQL Stored Objects & API Reference

### 5.1 `book_ticket` Procedure
- **Signature:** `book_ticket(p_passenger NUMBER, p_schedule NUMBER, p_class VARCHAR2, p_from VARCHAR2, p_to VARCHAR2, p_mode VARCHAR2 DEFAULT 'UPI', p_pnr OUT NUMBER, p_status OUT VARCHAR2)`
- **Behavior:**
  1. Validates passenger existence (`-20015` if missing).
  2. Acquires row lock (`FOR UPDATE`) on `train_schedule` to serialize seat allocation for this journey.
  3. Verifies schedule is `SCHEDULED` (`-20010` if closed).
  4. Enforces BR8: rejects if passenger already holds an active ticket (`-20017`).
  5. Selects earliest available `seat_id` in requested class.
  6. If free seat exists: allocates seat and sets status to `CONFIRMED`.
  7. If coach is full: assigns `seat_id = NULL` and status to `WAITLIST`.
  8. Inserts reservation and payment record atomically.
  9. Contains a bounded retry loop catching `DUP_VAL_ON_INDEX` for bulletproof concurrent seat conflict defense.

### 5.2 `cancel_ticket` Procedure
- **Signature:** `cancel_ticket(p_pnr NUMBER, p_reason VARCHAR2)`
- **Behavior:**
  1. Locks target reservation row (`FOR UPDATE OF r.status`).
  2. Rejects if PNR does not exist (`-20016`).
  3. Rejects if ticket is already CANCELLED or COMPLETED (`-20012`).
  4. Calculates hours remaining to departure (`(journey_date + dep_time - SYSDATE) * 24`); rejects if departed (`-20013`).
  5. Applies BR15 refund policy.
  6. Releases seat (`seat_id = NULL`), records cancellation, updates payment status.
  7. If a seat was released: queries the earliest waitlisted ticket in FIFO order (`ORDER BY booking_date, pnr`), updates to `CONFIRMED` on the released seat, and logs the promotion.

### 5.3 `fn_capacity_risk` Function & `prc_capacity_risk_report` Procedure
- **Function:** Reads operational parameters from `risk_threshold` table. Returns `CAPACITY REQUIRED`, `HIGH DEMAND`, or `NORMAL`.
- **Procedure:** Refreshes daily log in `capacity_risk_log` from view `v_train_utilization` and outputs an executive summary via `DBMS_OUTPUT`.

---

## 6. Execution & Setup Instructions

### Prerequisites
- Oracle Database 19c, 21c, 23ai, or 26ai.
- Privileges: `CONNECT, RESOURCE, CREATE VIEW, CREATE PROCEDURE, CREATE SEQUENCE, CREATE TRIGGER`.

### Modular Setup Execution
In SQL*Plus:
```sql
@parts/run_all.sql
```
This runs:
1. `01_ddl.sql`: Creates schema, constraints, sequences, indexes, and triggers.
2. `02_data.sql`: Loads static reference stations, routes, coaches, and sample reservations.
3. `02b_seat.sql`: Idempotent seat population verification.
4. `03_dml.sql`: Applies alter statements, DML updates, integrity tests, and stored procedures.
5. `04_queries.sql`: Compiles views, runs analytical queries Q1–Q10, advanced queries A1–A9, and capacity risk module.

### Automated Testing
From the terminal:
```bash
python tests/run_tests.py
python tests/test_concurrency_race.py
```
Or directly within SQL*Plus:
```sql
@tests/run_all_tests.sql
```
