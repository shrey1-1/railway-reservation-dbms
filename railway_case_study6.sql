-- =====================================================================================
--  CASE STUDY 6 : RAILWAY RESERVATION AND PASSENGER SERVICE MANAGEMENT SYSTEM
--  Course : BCSE302P - Database Systems Lab            DBMS : Oracle Database (SQL*Plus)
--  Script is re-runnable: Part 0 drops every object created by this script.
-- =====================================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET FEEDBACK ON
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY';
COLUMN full_name        FORMAT A20
COLUMN seat             FORMAT A26
COLUMN boarding         FORMAT A27
COLUMN destination      FORMAT A27
COLUMN class_name       FORMAT A20
COLUMN segment          FORMAT A30
COLUMN reason           FORMAT A24
COLUMN trains_cancelled FORMAT A30
COLUMN current_status   FORMAT A18
COLUMN what_if_status   FORMAT A18
COLUMN traveller_type   FORMAT A10
COLUMN tbl              FORMAT A15
COLUMN home_city        FORMAT A16
COLUMN city             FORMAT A18

-- =====================================================================================
--  PART 0 : CLEAN-UP
-- =====================================================================================
BEGIN
  FOR v IN (SELECT view_name FROM user_views
            WHERE view_name IN ('V_RESERVATION_PERFORMANCE','V_TRAIN_UTILIZATION','V_TICKET_DETAILS')) LOOP
    EXECUTE IMMEDIATE 'DROP VIEW ' || v.view_name;
  END LOOP;
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('CAPACITY_RISK_LOG','RISK_THRESHOLD','CANCELLATION','PAYMENT','RESERVATION',
                                 'PASSENGER','TRAIN_SCHEDULE','SEAT','COACH','COACH_CLASS','TRAIN',
                                 'ROUTE_STOP','ROUTE','STATION')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name IN ('SEQ_PNR','SEQ_PAYMENT','SEQ_CANCEL')) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;
END;
/

-- =====================================================================================
--  PART 1 : DDL - TABLE CREATION WITH INTEGRITY CONSTRAINTS
-- =====================================================================================

-- 1.1 STATION : every railway station served by the network
CREATE TABLE station (
  station_code   VARCHAR2(5)   CONSTRAINT pk_station PRIMARY KEY,
  station_name   VARCHAR2(60)  NOT NULL,
  city           VARCHAR2(40)  NOT NULL,
  state          VARCHAR2(30)  NOT NULL,
  rail_zone      VARCHAR2(5)   NOT NULL,
  platforms      NUMBER(2)     DEFAULT 1 NOT NULL
                 CONSTRAINT ck_station_pf CHECK (platforms BETWEEN 1 AND 30),
  CONSTRAINT ck_station_code CHECK (station_code = UPPER(station_code))
);

-- 1.2 ROUTE : a named corridor between an origin and a destination
CREATE TABLE route (
  route_id       NUMBER(4)     CONSTRAINT pk_route PRIMARY KEY,
  route_name     VARCHAR2(60)  NOT NULL CONSTRAINT uq_route_name UNIQUE,
  origin_code    VARCHAR2(5)   NOT NULL CONSTRAINT fk_route_origin REFERENCES station(station_code),
  dest_code      VARCHAR2(5)   NOT NULL CONSTRAINT fk_route_dest   REFERENCES station(station_code),
  distance_km    NUMBER(5)     NOT NULL CONSTRAINT ck_route_km CHECK (distance_km > 0),
  CONSTRAINT ck_route_ends CHECK (origin_code <> dest_code)
);

-- 1.3 ROUTE_STOP : ordered list of stations on a route (resolves the M:N ROUTE-STATION)
CREATE TABLE route_stop (
  route_id       NUMBER(4)     CONSTRAINT fk_rs_route REFERENCES route(route_id) ON DELETE CASCADE,
  stop_seq       NUMBER(2)     CONSTRAINT ck_rs_seq CHECK (stop_seq >= 1),
  station_code   VARCHAR2(5)   NOT NULL CONSTRAINT fk_rs_station REFERENCES station(station_code),
  km_from_origin NUMBER(5)     NOT NULL CONSTRAINT ck_rs_km CHECK (km_from_origin >= 0),
  CONSTRAINT pk_route_stop PRIMARY KEY (route_id, stop_seq),
  CONSTRAINT uq_rs_station UNIQUE (route_id, station_code)
);

-- 1.4 TRAIN : a train service that always runs on one route
CREATE TABLE train (
  train_no       NUMBER(5)     CONSTRAINT pk_train PRIMARY KEY
                 CONSTRAINT ck_train_no CHECK (train_no BETWEEN 10000 AND 99999),
  train_name     VARCHAR2(50)  NOT NULL,
  train_type     VARCHAR2(15)  NOT NULL
                 CONSTRAINT ck_train_type CHECK (train_type IN ('SUPERFAST','EXPRESS','SHATABDI','TEJAS','INTERCITY','MAIL')),
  route_id       NUMBER(4)     NOT NULL CONSTRAINT fk_train_route REFERENCES route(route_id),
  dep_time       VARCHAR2(5)   NOT NULL
                 CONSTRAINT ck_train_dep CHECK (REGEXP_LIKE(dep_time, '^([01][0-9]|2[0-3]):[0-5][0-9]$')),
  run_days       VARCHAR2(7)   DEFAULT 'YYYYYYY' NOT NULL
                 CONSTRAINT ck_train_days CHECK (REGEXP_LIKE(run_days, '^[YN]{7}$')),
  is_active      CHAR(1)       DEFAULT 'Y' NOT NULL CONSTRAINT ck_train_active CHECK (is_active IN ('Y','N'))
);

-- 1.5 COACH_CLASS : travel class with fare rule and seats per coach
CREATE TABLE coach_class (
  class_code      VARCHAR2(3)  CONSTRAINT pk_coach_class PRIMARY KEY,
  class_name      VARCHAR2(30) NOT NULL,
  seats_per_coach NUMBER(3)    NOT NULL CONSTRAINT ck_cc_seats CHECK (seats_per_coach BETWEEN 1 AND 100),
  fare_per_km     NUMBER(5,2)  NOT NULL CONSTRAINT ck_cc_fare  CHECK (fare_per_km > 0),
  reservation_fee NUMBER(5)    NOT NULL CONSTRAINT ck_cc_fee   CHECK (reservation_fee >= 0)
);

-- 1.6 COACH : physical coach attached to a train (weak entity identified by train + label)
CREATE TABLE coach (
  coach_id       NUMBER(5)     CONSTRAINT pk_coach PRIMARY KEY,
  train_no       NUMBER(5)     NOT NULL CONSTRAINT fk_coach_train REFERENCES train(train_no) ON DELETE CASCADE,
  coach_label    VARCHAR2(4)   NOT NULL,
  class_code     VARCHAR2(3)   NOT NULL CONSTRAINT fk_coach_class REFERENCES coach_class(class_code),
  CONSTRAINT uq_coach_label UNIQUE (train_no, coach_label)
);

-- 1.7 SEAT : individual seat / berth inside a coach
CREATE TABLE seat (
  seat_id        NUMBER(7)     CONSTRAINT pk_seat PRIMARY KEY,
  coach_id       NUMBER(5)     NOT NULL CONSTRAINT fk_seat_coach REFERENCES coach(coach_id) ON DELETE CASCADE,
  seat_no        NUMBER(3)     NOT NULL CONSTRAINT ck_seat_no CHECK (seat_no >= 1),
  berth_type     VARCHAR2(12)  NOT NULL
                 CONSTRAINT ck_berth CHECK (berth_type IN ('LOWER','MIDDLE','UPPER','SIDE LOWER','SIDE UPPER',
                                                           'WINDOW','AISLE','MIDDLE SEAT')),
  CONSTRAINT uq_seat UNIQUE (coach_id, seat_no)
);

-- 1.8 TRAIN_SCHEDULE : one actual run (journey) of a train on a date
CREATE TABLE train_schedule (
  schedule_id    NUMBER(6)     CONSTRAINT pk_schedule PRIMARY KEY,
  train_no       NUMBER(5)     NOT NULL CONSTRAINT fk_sched_train REFERENCES train(train_no),
  journey_date   DATE          NOT NULL,
  sched_status   VARCHAR2(10)  DEFAULT 'SCHEDULED' NOT NULL
                 CONSTRAINT ck_sched_status CHECK (sched_status IN ('SCHEDULED','DEPARTED','COMPLETED','CANCELLED')),
  CONSTRAINT uq_sched UNIQUE (train_no, journey_date),
  CONSTRAINT ck_sched_date CHECK (journey_date = TRUNC(journey_date))
);

-- 1.9 PASSENGER : registered traveller
CREATE TABLE passenger (
  passenger_id   NUMBER(6)     CONSTRAINT pk_passenger PRIMARY KEY,
  full_name      VARCHAR2(60)  NOT NULL,
  gender         CHAR(1)       NOT NULL CONSTRAINT ck_pass_gender CHECK (gender IN ('M','F','T')),
  dob            DATE          NOT NULL,
  phone          VARCHAR2(10)  NOT NULL CONSTRAINT uq_pass_phone UNIQUE
                 CONSTRAINT ck_pass_phone CHECK (REGEXP_LIKE(phone, '^[6-9][0-9]{9}$')),
  email          VARCHAR2(60)  CONSTRAINT uq_pass_email UNIQUE
                 CONSTRAINT ck_pass_email CHECK (REGEXP_LIKE(email, '^[A-Za-z0-9._]+@[A-Za-z0-9.]+\.[A-Za-z]{2,}$')),
  city           VARCHAR2(40),
  registered_on  DATE          DEFAULT SYSDATE NOT NULL
);

-- 1.10 RESERVATION : one ticket (PNR) = one passenger on one journey; holds the ticket status
CREATE TABLE reservation (
  pnr            NUMBER(10)    CONSTRAINT pk_reservation PRIMARY KEY,
  passenger_id   NUMBER(6)     NOT NULL CONSTRAINT fk_res_pass  REFERENCES passenger(passenger_id),
  schedule_id    NUMBER(6)     NOT NULL CONSTRAINT fk_res_sched REFERENCES train_schedule(schedule_id),
  class_code     VARCHAR2(3)   NOT NULL CONSTRAINT fk_res_class REFERENCES coach_class(class_code),
  seat_id        NUMBER(7)     CONSTRAINT fk_res_seat REFERENCES seat(seat_id),
  from_station   VARCHAR2(5)   NOT NULL CONSTRAINT fk_res_from REFERENCES station(station_code),
  to_station     VARCHAR2(5)   NOT NULL CONSTRAINT fk_res_to   REFERENCES station(station_code),
  booking_date   DATE          DEFAULT TRUNC(SYSDATE) NOT NULL,
  fare           NUMBER(8,2)   CONSTRAINT ck_res_fare CHECK (fare > 0),
  status         VARCHAR2(10)  DEFAULT 'CONFIRMED' NOT NULL
                 CONSTRAINT ck_res_status CHECK (status IN ('CONFIRMED','WAITLIST','CANCELLED','COMPLETED')),
  CONSTRAINT ck_res_stations CHECK (from_station <> to_station),
  -- a confirmed / completed ticket must hold a seat; a waitlisted / cancelled one must not
  CONSTRAINT ck_res_seat_status CHECK (
        (status IN ('CONFIRMED','COMPLETED') AND seat_id IS NOT NULL)
     OR (status IN ('WAITLIST','CANCELLED')  AND seat_id IS NULL))
);

-- No seat can be sold twice on the same journey (function-based unique index ignores NULL seats)
CREATE UNIQUE INDEX ux_res_seat_journey
  ON reservation (CASE WHEN seat_id IS NOT NULL THEN schedule_id END, seat_id);
-- A passenger cannot hold two active tickets on the same journey
CREATE UNIQUE INDEX ux_res_pass_journey
  ON reservation (CASE WHEN status <> 'CANCELLED' THEN passenger_id END,
                  CASE WHEN status <> 'CANCELLED' THEN schedule_id  END);
CREATE INDEX ix_res_schedule_status ON reservation (schedule_id, status);

-- 1.11 PAYMENT : exactly one payment per reservation (1:1)
CREATE TABLE payment (
  payment_id     NUMBER(8)     CONSTRAINT pk_payment PRIMARY KEY,
  pnr            NUMBER(10)    NOT NULL CONSTRAINT uq_pay_pnr UNIQUE
                 CONSTRAINT fk_pay_res REFERENCES reservation(pnr) ON DELETE CASCADE,
  amount         NUMBER(8,2)   NOT NULL CONSTRAINT ck_pay_amt CHECK (amount > 0),
  pay_mode       VARCHAR2(10)  NOT NULL CONSTRAINT ck_pay_mode CHECK (pay_mode IN ('UPI','CARD','NETBANKING','WALLET','CASH')),
  paid_on        DATE          NOT NULL,
  pay_status     VARCHAR2(14)  DEFAULT 'SUCCESS' NOT NULL
                 CONSTRAINT ck_pay_status CHECK (pay_status IN ('SUCCESS','REFUNDED','PARTIAL_REFUND'))
);

-- 1.12 CANCELLATION : at most one cancellation per reservation (1:0..1)
CREATE TABLE cancellation (
  cancel_id      NUMBER(8)     CONSTRAINT pk_cancellation PRIMARY KEY,
  pnr            NUMBER(10)    NOT NULL CONSTRAINT uq_cancel_pnr UNIQUE
                 CONSTRAINT fk_cancel_res REFERENCES reservation(pnr) ON DELETE CASCADE,
  cancelled_on   DATE          NOT NULL,
  refund_amount  NUMBER(8,2)   DEFAULT 0 NOT NULL CONSTRAINT ck_cancel_refund CHECK (refund_amount >= 0),
  reason         VARCHAR2(60)
);

CREATE SEQUENCE seq_pnr     START WITH 4200001001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_payment START WITH 901001     INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cancel  START WITH 701001     INCREMENT BY 1 NOCACHE;

-- -------------------------------------------------------------------------------------
-- 1.13 TRIGGER : business rules that span several tables (cannot be CHECK constraints)
--   R1 boarding station must come before the destination on the train's route
--   R2 the seat must belong to a coach of THIS train and of the booked class
--   R3 a ticket cannot be booked after the journey date
--   R4 fare = max(distance, 50 km) * fare_per_km + reservation fee  (auto-calculated)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_reservation_validate
BEFORE INSERT OR UPDATE OF schedule_id, class_code, seat_id, from_station, to_station, fare
ON reservation
FOR EACH ROW
DECLARE
  v_train     train.train_no%TYPE;
  v_route     train.route_id%TYPE;
  v_jdate     train_schedule.journey_date%TYPE;
  v_from_seq  route_stop.stop_seq%TYPE;
  v_to_seq    route_stop.stop_seq%TYPE;
  v_from_km   route_stop.km_from_origin%TYPE;
  v_to_km     route_stop.km_from_origin%TYPE;
  v_seat_trn  train.train_no%TYPE;
  v_seat_cls  coach_class.class_code%TYPE;
  v_rate      coach_class.fare_per_km%TYPE;
  v_fee       coach_class.reservation_fee%TYPE;
BEGIN
  SELECT t.train_no, t.route_id, s.journey_date
    INTO v_train, v_route, v_jdate
    FROM train_schedule s JOIN train t ON t.train_no = s.train_no
   WHERE s.schedule_id = :NEW.schedule_id;

  -- R1
  BEGIN
    SELECT stop_seq, km_from_origin INTO v_from_seq, v_from_km
      FROM route_stop WHERE route_id = v_route AND station_code = :NEW.from_station;
    SELECT stop_seq, km_from_origin INTO v_to_seq, v_to_km
      FROM route_stop WHERE route_id = v_route AND station_code = :NEW.to_station;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Station is not on the route of train ' || v_train);
  END;
  IF v_from_seq >= v_to_seq THEN
    RAISE_APPLICATION_ERROR(-20002, 'Boarding station must come before destination on the route');
  END IF;

  -- R2
  IF :NEW.seat_id IS NOT NULL THEN
    SELECT c.train_no, c.class_code INTO v_seat_trn, v_seat_cls
      FROM seat st JOIN coach c ON c.coach_id = st.coach_id
     WHERE st.seat_id = :NEW.seat_id;
    IF v_seat_trn <> v_train OR v_seat_cls <> :NEW.class_code THEN
      RAISE_APPLICATION_ERROR(-20003, 'Seat ' || :NEW.seat_id || ' does not belong to train '
                              || v_train || ' / class ' || :NEW.class_code);
    END IF;
  END IF;

  -- R3
  IF INSERTING AND :NEW.booking_date > v_jdate THEN
    RAISE_APPLICATION_ERROR(-20004, 'Booking date cannot be after the journey date');
  END IF;

  -- R4
  IF :NEW.fare IS NULL THEN
    SELECT fare_per_km, reservation_fee INTO v_rate, v_fee
      FROM coach_class WHERE class_code = :NEW.class_code;
    :NEW.fare := ROUND(GREATEST(v_to_km - v_from_km, 50) * v_rate + v_fee, 0);
  END IF;
END;
/

-- =====================================================================================
--  PART 2 : DML - SAMPLE DATA
-- =====================================================================================
-- 2.1 STATION
INSERT INTO station VALUES ('MAS', 'Chennai Central', 'Chennai', 'Tamil Nadu', 'SR', 17);
INSERT INTO station VALUES ('KPD', 'Katpadi Junction', 'Vellore', 'Tamil Nadu', 'SR', 5);
INSERT INTO station VALUES ('JTJ', 'Jolarpettai Junction', 'Jolarpettai', 'Tamil Nadu', 'SR', 5);
INSERT INTO station VALUES ('SBC', 'KSR Bengaluru City', 'Bengaluru', 'Karnataka', 'SWR', 10);
INSERT INTO station VALUES ('VM', 'Villupuram Junction', 'Villupuram', 'Tamil Nadu', 'SR', 6);
INSERT INTO station VALUES ('TPJ', 'Tiruchchirappalli Junction', 'Tiruchirappalli', 'Tamil Nadu', 'SR', 8);
INSERT INTO station VALUES ('DG', 'Dindigul Junction', 'Dindigul', 'Tamil Nadu', 'SR', 5);
INSERT INTO station VALUES ('MDU', 'Madurai Junction', 'Madurai', 'Tamil Nadu', 'SR', 7);
INSERT INTO station VALUES ('SA', 'Salem Junction', 'Salem', 'Tamil Nadu', 'SR', 6);
INSERT INTO station VALUES ('ED', 'Erode Junction', 'Erode', 'Tamil Nadu', 'SR', 5);
INSERT INTO station VALUES ('CBE', 'Coimbatore Junction', 'Coimbatore', 'Tamil Nadu', 'SR', 6);
INSERT INTO station VALUES ('PGT', 'Palakkad Junction', 'Palakkad', 'Kerala', 'SR', 5);
INSERT INTO station VALUES ('ERS', 'Ernakulam Junction', 'Kochi', 'Kerala', 'SR', 6);
INSERT INTO station VALUES ('TVC', 'Thiruvananthapuram Central', 'Thiruvananthapuram', 'Kerala', 'SR', 5);

-- 2.2 ROUTE and ROUTE_STOP
INSERT INTO route VALUES (1, 'Chennai - Bengaluru', 'MAS', 'SBC', 359);
INSERT INTO route VALUES (2, 'Chennai - Madurai', 'MAS', 'MDU', 493);
INSERT INTO route VALUES (3, 'Chennai - Coimbatore', 'MAS', 'CBE', 494);
INSERT INTO route VALUES (4, 'Bengaluru - Ernakulam', 'SBC', 'ERS', 588);
INSERT INTO route_stop VALUES (1, 1, 'MAS', 0);
INSERT INTO route_stop VALUES (1, 2, 'KPD', 129);
INSERT INTO route_stop VALUES (1, 3, 'JTJ', 213);
INSERT INTO route_stop VALUES (1, 4, 'SBC', 359);
INSERT INTO route_stop VALUES (2, 1, 'MAS', 0);
INSERT INTO route_stop VALUES (2, 2, 'VM', 159);
INSERT INTO route_stop VALUES (2, 3, 'TPJ', 337);
INSERT INTO route_stop VALUES (2, 4, 'DG', 431);
INSERT INTO route_stop VALUES (2, 5, 'MDU', 493);
INSERT INTO route_stop VALUES (3, 1, 'MAS', 0);
INSERT INTO route_stop VALUES (3, 2, 'KPD', 129);
INSERT INTO route_stop VALUES (3, 3, 'JTJ', 213);
INSERT INTO route_stop VALUES (3, 4, 'SA', 334);
INSERT INTO route_stop VALUES (3, 5, 'ED', 394);
INSERT INTO route_stop VALUES (3, 6, 'CBE', 494);
INSERT INTO route_stop VALUES (4, 1, 'SBC', 0);
INSERT INTO route_stop VALUES (4, 2, 'SA', 198);
INSERT INTO route_stop VALUES (4, 3, 'ED', 258);
INSERT INTO route_stop VALUES (4, 4, 'CBE', 358);
INSERT INTO route_stop VALUES (4, 5, 'PGT', 412);
INSERT INTO route_stop VALUES (4, 6, 'ERS', 588);

-- 2.3 COACH_CLASS  (seats_per_coach is scaled down for demonstration)
INSERT INTO coach_class VALUES ('1A', 'First AC', 4, 4.20, 60);
INSERT INTO coach_class VALUES ('2A', 'AC 2-Tier', 8, 2.50, 50);
INSERT INTO coach_class VALUES ('3A', 'AC 3-Tier', 10, 1.80, 40);
INSERT INTO coach_class VALUES ('SL', 'Sleeper', 12, 0.65, 20);
INSERT INTO coach_class VALUES ('CC', 'AC Chair Car', 12, 1.45, 40);
INSERT INTO coach_class VALUES ('EC', 'Executive Chair Car', 8, 2.90, 60);

-- 2.4 TRAIN
INSERT INTO train (train_no, train_name, train_type, route_id, dep_time) VALUES (12639, 'Brindavan Express', 'SUPERFAST', 1, '07:50');
INSERT INTO train (train_no, train_name, train_type, route_id, dep_time) VALUES (12607, 'Lalbagh Express', 'SUPERFAST', 1, '15:35');
INSERT INTO train (train_no, train_name, train_type, route_id, dep_time) VALUES (12027, 'Chennai Shatabdi', 'SHATABDI', 1, '17:30');
INSERT INTO train (train_no, train_name, train_type, route_id, dep_time) VALUES (12635, 'Vaigai Express', 'SUPERFAST', 2, '13:50');
INSERT INTO train (train_no, train_name, train_type, route_id, dep_time) VALUES (12637, 'Pandian Express', 'SUPERFAST', 2, '21:40');
INSERT INTO train (train_no, train_name, train_type, route_id, dep_time) VALUES (22671, 'Madurai Tejas', 'TEJAS', 2, '06:00');
INSERT INTO train (train_no, train_name, train_type, route_id, dep_time) VALUES (12675, 'Kovai Express', 'SUPERFAST', 3, '06:10');
INSERT INTO train (train_no, train_name, train_type, route_id, dep_time) VALUES (12671, 'Nilgiri Express', 'SUPERFAST', 3, '21:05');
INSERT INTO train (train_no, train_name, train_type, route_id, dep_time) VALUES (12677, 'Ernakulam Intercity', 'INTERCITY', 4, '06:10');

-- 2.5 COACH
INSERT INTO coach VALUES (1, 12639, 'C1', 'CC');
INSERT INTO coach VALUES (2, 12639, 'C2', 'CC');
INSERT INTO coach VALUES (3, 12639, 'E1', 'EC');
INSERT INTO coach VALUES (4, 12607, 'C1', 'CC');
INSERT INTO coach VALUES (5, 12607, 'C2', 'CC');
INSERT INTO coach VALUES (6, 12607, 'C3', 'CC');
INSERT INTO coach VALUES (7, 12027, 'C1', 'CC');
INSERT INTO coach VALUES (8, 12027, 'C2', 'CC');
INSERT INTO coach VALUES (9, 12027, 'E1', 'EC');
INSERT INTO coach VALUES (10, 12635, 'C1', 'CC');
INSERT INTO coach VALUES (11, 12635, 'C2', 'CC');
INSERT INTO coach VALUES (12, 12635, 'C3', 'CC');
INSERT INTO coach VALUES (13, 12637, 'S1', 'SL');
INSERT INTO coach VALUES (14, 12637, 'S2', 'SL');
INSERT INTO coach VALUES (15, 12637, 'B1', '3A');
INSERT INTO coach VALUES (16, 12637, 'A1', '2A');
INSERT INTO coach VALUES (17, 22671, 'C1', 'CC');
INSERT INTO coach VALUES (18, 22671, 'C2', 'CC');
INSERT INTO coach VALUES (19, 22671, 'E1', 'EC');
INSERT INTO coach VALUES (20, 12675, 'C1', 'CC');
INSERT INTO coach VALUES (21, 12675, 'C2', 'CC');
INSERT INTO coach VALUES (22, 12675, 'E1', 'EC');
INSERT INTO coach VALUES (23, 12671, 'S1', 'SL');
INSERT INTO coach VALUES (24, 12671, 'S2', 'SL');
INSERT INTO coach VALUES (25, 12671, 'B1', '3A');
INSERT INTO coach VALUES (26, 12671, 'A1', '2A');
INSERT INTO coach VALUES (27, 12671, 'H1', '1A');
INSERT INTO coach VALUES (28, 12677, 'C1', 'CC');
INSERT INTO coach VALUES (29, 12677, 'C2', 'CC');
INSERT INTO coach VALUES (30, 12677, 'E1', 'EC');


-- 2.6 SEAT : generated from COACH x COACH_CLASS (seat_id = coach_id*100 + seat_no)
--     berth pattern: SL/3A bay of 8, 2A bay of 6, 1A lower/upper, chair cars window/middle/aisle
INSERT INTO seat (seat_id, coach_id, seat_no, berth_type)
SELECT c.coach_id * 100 + n.lvl, c.coach_id, n.lvl,
       CASE
         WHEN c.class_code IN ('SL','3A') THEN
              DECODE(MOD(n.lvl, 8), 1,'LOWER', 2,'MIDDLE', 3,'UPPER', 4,'LOWER', 5,'MIDDLE', 6,'UPPER', 7,'SIDE LOWER', 'SIDE UPPER')
         WHEN c.class_code = '2A' THEN
              DECODE(MOD(n.lvl, 6), 1,'LOWER', 2,'UPPER', 3,'LOWER', 4,'UPPER', 5,'SIDE LOWER', 'SIDE UPPER')
         WHEN c.class_code = '1A' THEN DECODE(MOD(n.lvl, 2), 1, 'LOWER', 'UPPER')
         WHEN c.class_code = 'EC' THEN DECODE(MOD(n.lvl, 2), 1, 'WINDOW', 'AISLE')
         ELSE DECODE(MOD(n.lvl, 3), 1, 'WINDOW', 2, 'MIDDLE SEAT', 'AISLE')
       END
FROM   coach c
       JOIN coach_class cc ON cc.class_code = c.class_code
       JOIN (SELECT LEVEL AS lvl FROM dual CONNECT BY LEVEL <= 100) n ON n.lvl <= cc.seats_per_coach;

-- 2.7 TRAIN_SCHEDULE  (two completed journeys + one upcoming journey per train)
INSERT INTO train_schedule VALUES (101, 12639, DATE '2026-09-20', 'COMPLETED');
INSERT INTO train_schedule VALUES (102, 12639, DATE '2026-10-04', 'COMPLETED');
INSERT INTO train_schedule VALUES (103, 12639, DATE '2026-10-21', 'SCHEDULED');
INSERT INTO train_schedule VALUES (104, 12607, DATE '2026-09-21', 'COMPLETED');
INSERT INTO train_schedule VALUES (105, 12607, DATE '2026-10-05', 'COMPLETED');
INSERT INTO train_schedule VALUES (106, 12607, DATE '2026-10-22', 'SCHEDULED');
INSERT INTO train_schedule VALUES (107, 12027, DATE '2026-09-22', 'COMPLETED');
INSERT INTO train_schedule VALUES (108, 12027, DATE '2026-10-06', 'COMPLETED');
INSERT INTO train_schedule VALUES (109, 12027, DATE '2026-10-23', 'SCHEDULED');
INSERT INTO train_schedule VALUES (110, 12635, DATE '2026-09-23', 'COMPLETED');
INSERT INTO train_schedule VALUES (111, 12635, DATE '2026-10-07', 'COMPLETED');
INSERT INTO train_schedule VALUES (112, 12635, DATE '2026-10-24', 'SCHEDULED');
INSERT INTO train_schedule VALUES (113, 12637, DATE '2026-09-24', 'COMPLETED');
INSERT INTO train_schedule VALUES (114, 12637, DATE '2026-10-08', 'COMPLETED');
INSERT INTO train_schedule VALUES (115, 12637, DATE '2026-10-25', 'SCHEDULED');
INSERT INTO train_schedule VALUES (116, 22671, DATE '2026-09-25', 'COMPLETED');
INSERT INTO train_schedule VALUES (117, 22671, DATE '2026-10-09', 'COMPLETED');
INSERT INTO train_schedule VALUES (118, 22671, DATE '2026-10-21', 'SCHEDULED');
INSERT INTO train_schedule VALUES (119, 12675, DATE '2026-09-26', 'COMPLETED');
INSERT INTO train_schedule VALUES (120, 12675, DATE '2026-10-10', 'COMPLETED');
INSERT INTO train_schedule VALUES (121, 12675, DATE '2026-10-22', 'SCHEDULED');
INSERT INTO train_schedule VALUES (122, 12671, DATE '2026-09-27', 'COMPLETED');
INSERT INTO train_schedule VALUES (123, 12671, DATE '2026-10-11', 'COMPLETED');
INSERT INTO train_schedule VALUES (124, 12671, DATE '2026-10-23', 'SCHEDULED');
INSERT INTO train_schedule VALUES (125, 12677, DATE '2026-09-28', 'COMPLETED');
INSERT INTO train_schedule VALUES (126, 12677, DATE '2026-10-12', 'COMPLETED');
INSERT INTO train_schedule VALUES (127, 12677, DATE '2026-10-24', 'SCHEDULED');

-- 2.8 PASSENGER
INSERT INTO passenger VALUES (1, 'Balaji Mani', 'M', DATE '1993-07-10', '7624642010', 'balaji.mani1@mail.com', 'Kochi', DATE '2025-01-28');
INSERT INTO passenger VALUES (2, 'Ajay Thomas', 'M', DATE '1997-02-24', '8518184808', 'ajay.thomas2@mail.com', 'Vellore', DATE '2025-11-12');
INSERT INTO passenger VALUES (3, 'Nithya Balaji', 'F', DATE '2006-08-11', '8386632201', 'nithya.balaji3@mail.com', 'Chennai', DATE '2025-04-03');
INSERT INTO passenger VALUES (4, 'Manoj Chandran', 'M', DATE '1958-03-25', '8935800437', 'manoj.chandran4@mail.com', 'Chennai', DATE '2025-09-28');
INSERT INTO passenger VALUES (5, 'Priya Pandian', 'F', DATE '1982-11-04', '7031005178', 'priya.pandian5@mail.com', 'Tiruchirappalli', DATE '2025-08-26');
INSERT INTO passenger VALUES (6, 'Janani Shankar', 'F', DATE '1983-09-28', '7551561306', 'janani.shankar6@mail.com', 'Bengaluru', DATE '2025-04-19');
INSERT INTO passenger VALUES (7, 'Gayathri Varma', 'F', DATE '1978-12-16', '7600100795', 'gayathri.varma7@mail.com', 'Palakkad', DATE '2025-12-14');
INSERT INTO passenger VALUES (8, 'Kishore Kumar', 'M', DATE '1980-06-21', '9571985370', 'kishore.kumar8@mail.com', 'Kochi', DATE '2025-11-12');
INSERT INTO passenger VALUES (9, 'Fathima Elango', 'F', DATE '1976-03-20', '7782480858', 'fathima.elango9@mail.com', 'Chennai', DATE '2025-03-15');
INSERT INTO passenger VALUES (10, 'Divya Arumugam', 'F', DATE '2004-11-28', '6301041973', 'divya.arumugam10@mail.com', 'Madurai', DATE '2026-02-09');
INSERT INTO passenger VALUES (11, 'Padma Kumar', 'F', DATE '1996-03-05', '8580163320', 'padma.kumar11@mail.com', 'Madurai', DATE '2025-12-21');
INSERT INTO passenger VALUES (12, 'Deepa Anand', 'F', DATE '1984-03-06', '6806765076', 'deepa.anand12@mail.com', 'Kochi', DATE '2025-04-06');
INSERT INTO passenger VALUES (13, 'Charulatha Sundar', 'F', DATE '1983-11-20', '9979661154', 'charulatha.sundar13@mail.com', 'Bengaluru', DATE '2025-10-07');
INSERT INTO passenger VALUES (14, 'Asha Mani', 'F', DATE '1979-04-17', '8953509953', 'asha.mani14@mail.com', 'Kochi', DATE '2025-10-05');
INSERT INTO passenger VALUES (15, 'Ajay Reddy', 'M', DATE '2007-03-11', '7767528908', 'ajay.reddy15@mail.com', 'Chennai', DATE '2025-09-18');
INSERT INTO passenger VALUES (16, 'Krishna Velu', 'M', DATE '1950-01-04', '8629223373', 'krishna.velu16@mail.com', 'Chennai', DATE '2026-03-09');
INSERT INTO passenger VALUES (17, 'Revathi Selvam', 'F', DATE '1996-05-11', '6175890092', 'revathi.selvam17@mail.com', 'Erode', DATE '2025-09-15');
INSERT INTO passenger VALUES (18, 'Asha Hegde', 'F', DATE '1996-02-14', '9214142429', 'asha.hegde18@mail.com', 'Bengaluru', DATE '2026-03-03');
INSERT INTO passenger VALUES (19, 'Sangeetha Mani', 'F', DATE '1977-04-22', '9228399566', 'sangeetha.mani19@mail.com', 'Dindigul', DATE '2025-07-10');
INSERT INTO passenger VALUES (20, 'Charulatha Anand', 'F', DATE '2007-12-14', '9919303147', 'charulatha.anand20@mail.com', 'Bengaluru', DATE '2025-07-05');
INSERT INTO passenger VALUES (21, 'Shalini Raman', 'F', DATE '2000-05-21', '9600239801', 'shalini.raman21@mail.com', 'Chennai', DATE '2025-11-07');
INSERT INTO passenger VALUES (22, 'Rajesh Sundar', 'M', DATE '1998-04-24', '7124396058', 'rajesh.sundar22@mail.com', 'Coimbatore', DATE '2026-01-23');
INSERT INTO passenger VALUES (23, 'Nandhini Prasad', 'F', DATE '1961-11-20', '7123638170', 'nandhini.prasad23@mail.com', 'Dindigul', DATE '2025-03-30');
INSERT INTO passenger VALUES (24, 'Saranya Mani', 'F', DATE '1983-04-14', '6587233095', 'saranya.mani24@mail.com', 'Coimbatore', DATE '2026-05-13');
INSERT INTO passenger VALUES (25, 'Sneha Chandran', 'F', DATE '2006-05-24', '8427673333', 'sneha.chandran25@mail.com', 'Madurai', DATE '2025-01-05');
INSERT INTO passenger VALUES (26, 'Lakshmi Rao', 'F', DATE '1984-05-27', '8524170066', 'lakshmi.rao26@mail.com', 'Dindigul', DATE '2025-03-12');
INSERT INTO passenger VALUES (27, 'Nithya Natarajan', 'F', DATE '2005-09-08', '8489644350', 'nithya.natarajan27@mail.com', 'Coimbatore', DATE '2025-07-13');
INSERT INTO passenger VALUES (28, 'Kavya Mohan', 'F', DATE '1988-01-23', '8810573992', 'kavya.mohan28@mail.com', 'Coimbatore', DATE '2025-05-11');
INSERT INTO passenger VALUES (29, 'Lakshmi Pillai', 'F', DATE '1972-08-15', '8586367659', 'lakshmi.pillai29@mail.com', 'Palakkad', DATE '2026-02-27');
INSERT INTO passenger VALUES (30, 'Swathi Rao', 'F', DATE '1996-09-04', '8318641473', 'swathi.rao30@mail.com', 'Chennai', DATE '2025-01-20');
INSERT INTO passenger VALUES (31, 'Arjun Rao', 'M', DATE '2004-02-17', '9605996205', 'arjun.rao31@mail.com', 'Vellore', DATE '2025-02-25');
INSERT INTO passenger VALUES (32, 'Sanjay Balaji', 'M', DATE '1990-10-15', '9580661102', 'sanjay.balaji32@mail.com', 'Chennai', DATE '2025-01-12');
INSERT INTO passenger VALUES (33, 'Deepak Mohan', 'M', DATE '2006-03-01', '6420732602', 'deepak.mohan33@mail.com', 'Tiruchirappalli', DATE '2025-02-17');
INSERT INTO passenger VALUES (34, 'Swathi Raman', 'F', DATE '2006-01-02', '6808075560', 'swathi.raman34@mail.com', 'Madurai', DATE '2025-11-05');
INSERT INTO passenger VALUES (35, 'Harini Hegde', 'F', DATE '1993-06-23', '7329673845', 'harini.hegde35@mail.com', 'Bengaluru', DATE '2026-05-06');
INSERT INTO passenger VALUES (36, 'Harini Mani', 'F', DATE '1980-12-15', '7429538128', 'harini.mani36@mail.com', 'Bengaluru', DATE '2025-05-03');
INSERT INTO passenger VALUES (37, 'Abdul Rajan', 'M', DATE '1997-06-14', '6525010491', 'abdul.rajan37@mail.com', 'Chennai', DATE '2025-05-08');
INSERT INTO passenger VALUES (38, 'Sowmya Thomas', 'F', DATE '1984-04-25', '6631761037', 'sowmya.thomas38@mail.com', 'Madurai', DATE '2025-09-01');
INSERT INTO passenger VALUES (39, 'Bharath Pillai', 'M', DATE '1985-09-01', '9234683135', 'bharath.pillai39@mail.com', 'Madurai', DATE '2025-07-16');
INSERT INTO passenger VALUES (40, 'Pradeep Varma', 'M', DATE '1986-08-26', '7316402012', 'pradeep.varma40@mail.com', 'Chennai', DATE '2025-05-04');
INSERT INTO passenger VALUES (41, 'Prakash Murugan', 'M', DATE '1980-05-25', '9927318461', 'prakash.murugan41@mail.com', 'Chennai', DATE '2026-01-12');
INSERT INTO passenger VALUES (42, 'Anand Velu', 'M', DATE '1981-10-28', '7569486552', 'anand.velu42@mail.com', 'Madurai', DATE '2025-03-04');
INSERT INTO passenger VALUES (43, 'Nithya Raghavan', 'F', DATE '1995-04-19', '6595562137', 'nithya.raghavan43@mail.com', 'Chennai', DATE '2025-03-29');
INSERT INTO passenger VALUES (44, 'Saranya Rajan', 'F', DATE '1995-02-26', '6864573595', 'saranya.rajan44@mail.com', 'Chennai', DATE '2025-08-01');
INSERT INTO passenger VALUES (45, 'Krishna Sankar', 'M', DATE '1970-04-07', '6282048616', 'krishna.sankar45@mail.com', 'Coimbatore', DATE '2026-01-20');
INSERT INTO passenger VALUES (46, 'Aravind Shankar', 'M', DATE '1986-05-12', '6274180000', 'aravind.shankar46@mail.com', 'Chennai', DATE '2025-03-27');
INSERT INTO passenger VALUES (47, 'Ashwin Subramanian', 'M', DATE '1971-04-23', '6965714329', 'ashwin.subramanian47@mail.com', 'Erode', DATE '2025-08-18');
INSERT INTO passenger VALUES (48, 'Ganesh Pillai', 'M', DATE '1971-06-23', '9902905088', 'ganesh.pillai48@mail.com', 'Coimbatore', DATE '2026-05-02');
INSERT INTO passenger VALUES (49, 'Gautham Sundar', 'M', DATE '1999-01-28', '7698396784', 'gautham.sundar49@mail.com', 'Bengaluru', DATE '2025-11-30');
INSERT INTO passenger VALUES (50, 'Ramesh Natarajan', 'M', DATE '1971-05-03', '7699937880', 'ramesh.natarajan50@mail.com', 'Madurai', DATE '2025-02-03');
INSERT INTO passenger VALUES (51, 'Padma Hegde', 'F', DATE '1970-05-20', '6506143417', 'padma.hegde51@mail.com', 'Coimbatore', DATE '2026-04-19');
INSERT INTO passenger VALUES (52, 'Tarun Ganesh', 'M', DATE '1998-12-24', '7587823967', 'tarun.ganesh52@mail.com', 'Chennai', DATE '2025-11-22');
INSERT INTO passenger VALUES (53, 'Bhavani Prasad', 'F', DATE '1987-04-16', '6581614724', 'bhavani.prasad53@mail.com', 'Coimbatore', DATE '2025-06-30');
INSERT INTO passenger VALUES (54, 'Ishwarya Chandran', 'F', DATE '1982-08-03', '7033762392', 'ishwarya.chandran54@mail.com', 'Coimbatore', DATE '2025-01-08');
INSERT INTO passenger VALUES (55, 'Balaji Sundar', 'M', DATE '1987-02-15', '7184224869', 'balaji.sundar55@mail.com', 'Coimbatore', DATE '2025-05-02');
INSERT INTO passenger VALUES (56, 'Deepa Sundar', 'F', DATE '2005-09-25', '8429314216', 'deepa.sundar56@mail.com', 'Kochi', DATE '2025-05-23');
INSERT INTO passenger VALUES (57, 'Lakshmi Venkatesh', 'F', DATE '1990-03-15', '6020338834', 'lakshmi.venkatesh57@mail.com', 'Bengaluru', DATE '2025-06-26');
INSERT INTO passenger VALUES (58, 'Suresh Elango', 'M', DATE '1962-03-19', '7883438194', 'suresh.elango58@mail.com', 'Erode', DATE '2026-02-23');
INSERT INTO passenger VALUES (59, 'Ishwarya Hegde', 'F', DATE '1992-03-22', '8188663225', 'ishwarya.hegde59@mail.com', 'Tiruchirappalli', DATE '2025-09-11');
INSERT INTO passenger VALUES (60, 'Karthik Murugan', 'M', DATE '1974-01-27', '9096196147', 'karthik.murugan60@mail.com', 'Chennai', DATE '2026-05-10');
INSERT INTO passenger VALUES (61, 'Indhu Venkatesh', 'F', DATE '1990-07-22', '8550089936', 'indhu.venkatesh61@mail.com', 'Chennai', DATE '2026-04-28');
INSERT INTO passenger VALUES (62, 'Janani Chandran', 'F', DATE '1993-11-19', '6698239320', 'janani.chandran62@mail.com', 'Vellore', DATE '2025-05-10');
INSERT INTO passenger VALUES (63, 'Harini Nair', 'F', DATE '1982-04-10', '7329506808', 'harini.nair63@mail.com', 'Bengaluru', DATE '2026-01-18');
INSERT INTO passenger VALUES (64, 'Krishna Rajan', 'M', DATE '1970-06-24', '7767122694', 'krishna.rajan64@mail.com', 'Chennai', DATE '2025-08-23');
INSERT INTO passenger VALUES (65, 'Prakash Natarajan', 'M', DATE '1977-11-16', '7652086906', 'prakash.natarajan65@mail.com', 'Erode', DATE '2026-05-04');
INSERT INTO passenger VALUES (66, 'Anand Raghavan', 'M', DATE '1991-08-04', '6136552193', 'anand.raghavan66@mail.com', 'Bengaluru', DATE '2025-01-03');
INSERT INTO passenger VALUES (67, 'Mohammed Raghavan', 'M', DATE '1979-03-14', '8021785835', 'mohammed.raghavan67@mail.com', 'Chennai', DATE '2025-08-16');
INSERT INTO passenger VALUES (68, 'Aishwarya Iyer', 'F', DATE '2000-03-13', '6476826004', 'aishwarya.iyer68@mail.com', 'Chennai', DATE '2025-10-28');
INSERT INTO passenger VALUES (69, 'Aishwarya Thomas', 'F', DATE '2005-06-15', '6908145986', 'aishwarya.thomas69@mail.com', 'Chennai', DATE '2025-07-17');
INSERT INTO passenger VALUES (70, 'Pradeep Balaji', 'M', DATE '1984-08-24', '8269417042', 'pradeep.balaji70@mail.com', 'Chennai', DATE '2025-08-17');
INSERT INTO passenger VALUES (71, 'Deepa Nair', 'F', DATE '1983-08-10', '8878398724', 'deepa.nair71@mail.com', 'Tiruchirappalli', DATE '2025-03-28');
INSERT INTO passenger VALUES (72, 'Ramya Elango', 'F', DATE '2004-04-07', '8765117151', 'ramya.elango72@mail.com', 'Salem', DATE '2026-01-25');
INSERT INTO passenger VALUES (73, 'Yuvan Raghavan', 'M', DATE '1977-12-22', '8178109444', 'yuvan.raghavan73@mail.com', 'Salem', DATE '2026-02-14');
INSERT INTO passenger VALUES (74, 'Rajesh Anand', 'M', DATE '2007-03-20', '8692069081', 'rajesh.anand74@mail.com', 'Tiruchirappalli', DATE '2025-10-02');
INSERT INTO passenger VALUES (75, 'Siddharth Mani', 'M', DATE '1989-09-10', '9744754664', 'siddharth.mani75@mail.com', 'Tiruchirappalli', DATE '2025-05-15');
INSERT INTO passenger VALUES (76, 'Usha Chandran', 'F', DATE '1999-08-08', '7546180915', 'usha.chandran76@mail.com', 'Madurai', DATE '2025-06-04');
INSERT INTO passenger VALUES (77, 'Krishna Krishnan', 'M', DATE '1959-04-10', '7910238707', 'krishna.krishnan77@mail.com', 'Bengaluru', DATE '2025-08-09');
INSERT INTO passenger VALUES (78, 'Fathima Selvam', 'F', DATE '1974-08-13', '9731130212', 'fathima.selvam78@mail.com', 'Bengaluru', DATE '2025-01-31');
INSERT INTO passenger VALUES (79, 'Ramya Krishnan', 'F', DATE '1993-01-26', '8603196780', 'ramya.krishnan79@mail.com', 'Kochi', DATE '2025-06-02');
INSERT INTO passenger VALUES (80, 'Nandhini Menon', 'F', DATE '1977-12-21', '8860132984', 'nandhini.menon80@mail.com', 'Palakkad', DATE '2025-12-07');
INSERT INTO passenger VALUES (81, 'Ramesh Selvam', 'M', DATE '1989-09-12', '8806635907', 'ramesh.selvam81@mail.com', 'Chennai', DATE '2025-07-19');
INSERT INTO passenger VALUES (82, 'Sangeetha Krishnan', 'F', DATE '1970-07-17', '9415978949', 'sangeetha.krishnan82@mail.com', 'Coimbatore', DATE '2025-11-15');
INSERT INTO passenger VALUES (83, 'Prakash Thomas', 'M', DATE '1981-04-18', '9382496945', 'prakash.thomas83@mail.com', 'Madurai', DATE '2026-03-19');
INSERT INTO passenger VALUES (84, 'Pooja Thomas', 'F', DATE '1997-01-04', '7231182383', 'pooja.thomas84@mail.com', 'Tiruchirappalli', DATE '2025-03-31');
INSERT INTO passenger VALUES (85, 'Gautham Natarajan', 'M', DATE '1982-08-27', '7467558287', 'gautham.natarajan85@mail.com', 'Kochi', DATE '2025-09-20');
INSERT INTO passenger VALUES (86, 'Deepak Shankar', 'M', DATE '1970-09-03', '6125546108', 'deepak.shankar86@mail.com', 'Bengaluru', DATE '2025-04-22');
INSERT INTO passenger VALUES (87, 'Ajay Krishnan', 'M', DATE '1984-10-12', '6447067103', 'ajay.krishnan87@mail.com', 'Chennai', DATE '2025-05-01');
INSERT INTO passenger VALUES (88, 'Indhu Velu', 'F', DATE '1998-01-04', '6817936681', 'indhu.velu88@mail.com', 'Coimbatore', DATE '2025-06-24');
INSERT INTO passenger VALUES (89, 'Ramya Reddy', 'F', DATE '1984-11-14', '6691109758', 'ramya.reddy89@mail.com', 'Erode', DATE '2025-02-24');
INSERT INTO passenger VALUES (90, 'Vidya Sundar', 'F', DATE '1976-09-28', '9366020543', 'vidya.sundar90@mail.com', 'Palakkad', DATE '2025-11-01');
INSERT INTO passenger VALUES (91, 'Meera Raman', 'F', DATE '1972-06-08', '7476054727', 'meera.raman91@mail.com', 'Erode', DATE '2025-08-27');
INSERT INTO passenger VALUES (92, 'Surya Menon', 'M', DATE '1999-02-18', '9809158028', 'surya.menon92@mail.com', 'Bengaluru', DATE '2026-04-30');
INSERT INTO passenger VALUES (93, 'Yuvan Arumugam', 'M', DATE '2004-11-15', '9941014912', 'yuvan.arumugam93@mail.com', 'Bengaluru', DATE '2025-02-02');
INSERT INTO passenger VALUES (94, 'Vidya Pillai', 'F', DATE '1971-08-16', '8802279499', 'vidya.pillai94@mail.com', 'Madurai', DATE '2025-02-20');
INSERT INTO passenger VALUES (95, 'Saranya Elango', 'F', DATE '1983-03-14', '6274597255', 'saranya.elango95@mail.com', 'Kochi', DATE '2025-12-31');
INSERT INTO passenger VALUES (96, 'Sangeetha Pillai', 'F', DATE '1977-07-04', '8181339622', 'sangeetha.pillai96@mail.com', 'Chennai', DATE '2025-01-06');
INSERT INTO passenger VALUES (97, 'Swathi Pandian', 'F', DATE '1989-10-26', '8277161626', 'swathi.pandian97@mail.com', 'Chennai', DATE '2026-02-02');
INSERT INTO passenger VALUES (98, 'Preethi Thomas', 'F', DATE '1995-02-23', '7391802863', 'preethi.thomas98@mail.com', 'Chennai', DATE '2026-04-23');
INSERT INTO passenger VALUES (99, 'Suresh Ganesh', 'M', DATE '1983-11-03', '8342697161', 'suresh.ganesh99@mail.com', 'Madurai', DATE '2025-08-07');
INSERT INTO passenger VALUES (100, 'Deepak Venkatesh', 'M', DATE '1997-10-10', '7796328791', 'deepak.venkatesh100@mail.com', 'Dindigul', DATE '2026-02-27');
INSERT INTO passenger VALUES (101, 'Sneha Shankar', 'F', DATE '1975-09-14', '8036564465', 'sneha.shankar101@mail.com', 'Madurai', DATE '2025-10-12');
INSERT INTO passenger VALUES (102, 'Anand Nair', 'M', DATE '1986-08-10', '9792913727', 'anand.nair102@mail.com', 'Chennai', DATE '2026-03-13');
INSERT INTO passenger VALUES (103, 'Tarun Sankar', 'M', DATE '1976-12-25', '9174999413', 'tarun.sankar103@mail.com', 'Kochi', DATE '2025-07-03');
INSERT INTO passenger VALUES (104, 'Sangeetha Subramanian', 'F', DATE '1979-05-10', '6936548345', 'sangeetha.subramanian104@mail.com', 'Palakkad', DATE '2025-11-07');
INSERT INTO passenger VALUES (105, 'Ramesh Chandran', 'M', DATE '1999-04-20', '8748584266', 'ramesh.chandran105@mail.com', 'Bengaluru', DATE '2025-06-12');
INSERT INTO passenger VALUES (106, 'Gayathri Reddy', 'F', DATE '2000-11-04', '8435944827', 'gayathri.reddy106@mail.com', 'Madurai', DATE '2025-11-28');
INSERT INTO passenger VALUES (107, 'Arjun Velu', 'M', DATE '1984-10-13', '6400107169', 'arjun.velu107@mail.com', 'Coimbatore', DATE '2026-03-22');
INSERT INTO passenger VALUES (108, 'Indhu Rajan', 'F', DATE '1983-11-15', '8611387194', 'indhu.rajan108@mail.com', 'Palakkad', DATE '2025-07-13');
INSERT INTO passenger VALUES (109, 'Ashwin Raghavan', 'M', DATE '1994-06-13', '8850773933', 'ashwin.raghavan109@mail.com', 'Kochi', DATE '2025-05-09');
INSERT INTO passenger VALUES (110, 'Ramesh Krishnan', 'M', DATE '1970-06-14', '9047265866', 'ramesh.krishnan110@mail.com', 'Chennai', DATE '2025-11-05');
INSERT INTO passenger VALUES (111, 'Siddharth Iyer', 'M', DATE '1961-05-18', '6124721887', 'siddharth.iyer111@mail.com', 'Madurai', DATE '2026-01-30');
INSERT INTO passenger VALUES (112, 'Janani Hegde', 'F', DATE '1978-07-10', '8002395470', 'janani.hegde112@mail.com', 'Chennai', DATE '2025-04-16');
INSERT INTO passenger VALUES (113, 'Gautham Nair', 'M', DATE '1972-04-06', '6760998941', 'gautham.nair113@mail.com', 'Madurai', DATE '2025-07-07');
INSERT INTO passenger VALUES (114, 'Lakshmi Iyer', 'F', DATE '2000-10-18', '9110731822', 'lakshmi.iyer114@mail.com', 'Madurai', DATE '2025-12-13');
INSERT INTO passenger VALUES (115, 'Sangeetha Selvam', 'F', DATE '1986-11-20', '6310404816', 'sangeetha.selvam115@mail.com', 'Madurai', DATE '2025-03-06');
INSERT INTO passenger VALUES (116, 'Kalpana Selvam', 'F', DATE '2007-04-04', '6974778131', 'kalpana.selvam116@mail.com', 'Kochi', DATE '2025-02-23');
INSERT INTO passenger VALUES (117, 'Prakash Elango', 'M', DATE '1972-10-28', '9039506878', 'prakash.elango117@mail.com', 'Vellore', DATE '2025-03-12');
INSERT INTO passenger VALUES (118, 'Anitha Iyer', 'F', DATE '1996-09-24', '6812206401', 'anitha.iyer118@mail.com', 'Chennai', DATE '2026-01-30');
INSERT INTO passenger VALUES (119, 'Sangeetha Prasad', 'F', DATE '1983-06-18', '9204192941', 'sangeetha.prasad119@mail.com', 'Tiruchirappalli', DATE '2026-04-22');
INSERT INTO passenger VALUES (120, 'Ramesh Raghavan', 'M', DATE '1954-03-09', '7651314312', 'ramesh.raghavan120@mail.com', 'Coimbatore', DATE '2025-07-23');
INSERT INTO passenger VALUES (121, 'Ramya Pandian', 'F', DATE '1972-08-19', '9881895857', 'ramya.pandian121@mail.com', 'Madurai', DATE '2025-09-02');
INSERT INTO passenger VALUES (122, 'Bhavani Pillai', 'F', DATE '1990-03-26', '6308625186', 'bhavani.pillai122@mail.com', 'Coimbatore', DATE '2026-02-03');
INSERT INTO passenger VALUES (123, 'Usha Venkatesh', 'F', DATE '1995-03-14', '7289630669', 'usha.venkatesh123@mail.com', 'Chennai', DATE '2026-05-09');
INSERT INTO passenger VALUES (124, 'Harini Anand', 'F', DATE '1986-10-05', '7345069523', 'harini.anand124@mail.com', 'Bengaluru', DATE '2025-03-23');
INSERT INTO passenger VALUES (125, 'Deepa Raghavan', 'F', DATE '1992-05-01', '6207578787', 'deepa.raghavan125@mail.com', 'Bengaluru', DATE '2025-08-27');
INSERT INTO passenger VALUES (126, 'Aishwarya Babu', 'F', DATE '1981-07-03', '6394112842', 'aishwarya.babu126@mail.com', 'Kochi', DATE '2025-10-23');
INSERT INTO passenger VALUES (127, 'Revathi Sankar', 'F', DATE '1978-09-08', '7365268325', 'revathi.sankar127@mail.com', 'Chennai', DATE '2025-05-12');
INSERT INTO passenger VALUES (128, 'Hari Chandran', 'M', DATE '2004-09-03', '7498198158', 'hari.chandran128@mail.com', 'Vellore', DATE '2025-10-13');
INSERT INTO passenger VALUES (129, 'Charulatha Shankar', 'F', DATE '1995-03-06', '7208504003', 'charulatha.shankar129@mail.com', 'Chennai', DATE '2025-10-10');
INSERT INTO passenger VALUES (130, 'Ishwarya Sankar', 'F', DATE '1973-07-09', '9389928232', 'ishwarya.sankar130@mail.com', 'Chennai', DATE '2025-04-08');
INSERT INTO passenger VALUES (131, 'Indhu Sundar', 'F', DATE '1975-06-16', '6976531842', 'indhu.sundar131@mail.com', 'Bengaluru', DATE '2025-11-24');
INSERT INTO passenger VALUES (132, 'Gayathri Sankar', 'F', DATE '1989-05-26', '6596356436', 'gayathri.sankar132@mail.com', 'Chennai', DATE '2025-06-26');
INSERT INTO passenger VALUES (133, 'Bhavani Raman', 'F', DATE '1977-12-09', '9681978593', 'bhavani.raman133@mail.com', 'Bengaluru', DATE '2026-04-17');
INSERT INTO passenger VALUES (134, 'Harini Sankar', 'F', DATE '1954-03-09', '9421549993', 'harini.sankar134@mail.com', 'Vellore', DATE '2026-04-01');
INSERT INTO passenger VALUES (135, 'Asha Velu', 'F', DATE '1992-02-07', '8132656491', 'asha.velu135@mail.com', 'Madurai', DATE '2025-05-13');
INSERT INTO passenger VALUES (136, 'Rahul Srinivasan', 'M', DATE '1996-07-03', '9339526720', 'rahul.srinivasan136@mail.com', 'Erode', DATE '2025-05-26');
INSERT INTO passenger VALUES (137, 'Hari Raghavan', 'M', DATE '2000-12-27', '6994248844', 'hari.raghavan137@mail.com', 'Chennai', DATE '2025-02-04');
INSERT INTO passenger VALUES (138, 'Rajesh Mani', 'M', DATE '1983-02-07', '7580061680', 'rajesh.mani138@mail.com', 'Bengaluru', DATE '2025-01-06');
INSERT INTO passenger VALUES (139, 'Anitha Pillai', 'F', DATE '1955-04-01', '8100695442', 'anitha.pillai139@mail.com', 'Kochi', DATE '2025-05-10');
INSERT INTO passenger VALUES (140, 'Pradeep Babu', 'M', DATE '1986-07-22', '8580477595', 'pradeep.babu140@mail.com', 'Madurai', DATE '2026-01-17');
INSERT INTO passenger VALUES (141, 'Rajesh Venkatesh', 'M', DATE '1971-06-27', '9735709990', 'rajesh.venkatesh141@mail.com', 'Salem', DATE '2025-09-08');
INSERT INTO passenger VALUES (142, 'Joseph Kumar', 'M', DATE '1971-11-21', '8938249847', 'joseph.kumar142@mail.com', 'Vellore', DATE '2025-07-05');
INSERT INTO passenger VALUES (143, 'Preethi Reddy', 'F', DATE '2000-05-18', '8856424036', 'preethi.reddy143@mail.com', 'Chennai', DATE '2025-07-26');
INSERT INTO passenger VALUES (144, 'Hari Thomas', 'M', DATE '1994-02-21', '6465343469', 'hari.thomas144@mail.com', 'Chennai', DATE '2025-08-27');
INSERT INTO passenger VALUES (145, 'Anand Srinivasan', 'M', DATE '1971-11-20', '6507248656', 'anand.srinivasan145@mail.com', 'Coimbatore', DATE '2025-03-16');
INSERT INTO passenger VALUES (146, 'Vidya Murugan', 'F', DATE '1985-07-04', '8130648729', 'vidya.murugan146@mail.com', 'Madurai', DATE '2025-05-16');
INSERT INTO passenger VALUES (147, 'Aishwarya Pandian', 'F', DATE '2007-04-21', '7298783004', 'aishwarya.pandian147@mail.com', 'Madurai', DATE '2025-04-20');
INSERT INTO passenger VALUES (148, 'Sneha Pandian', 'F', DATE '1991-01-04', '6794574783', 'sneha.pandian148@mail.com', 'Chennai', DATE '2026-05-13');
INSERT INTO passenger VALUES (149, 'Surya Arumugam', 'M', DATE '1981-03-13', '7874603997', 'surya.arumugam149@mail.com', 'Bengaluru', DATE '2025-04-12');
INSERT INTO passenger VALUES (150, 'Nandhini Arumugam', 'F', DATE '1979-03-10', '9307250177', 'nandhini.arumugam150@mail.com', 'Bengaluru', DATE '2025-08-05');

-- 2.9 RESERVATION  (fare is calculated by trigger TRG_RESERVATION_VALIDATE)
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000001, 11, 101, 'CC', 205, 'MAS', 'SBC', DATE '2026-08-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000002, 16, 101, 'CC', 103, 'KPD', 'SBC', DATE '2026-08-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000003, 108, 101, 'CC', 112, 'MAS', 'SBC', DATE '2026-08-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000004, 65, 101, 'CC', 208, 'MAS', 'SBC', DATE '2026-08-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000005, 42, 101, 'CC', 206, 'JTJ', 'SBC', DATE '2026-08-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000006, 129, 101, 'CC', NULL, 'MAS', 'SBC', DATE '2026-08-15', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000007, 111, 101, 'CC', 207, 'KPD', 'JTJ', DATE '2026-08-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000008, 2, 101, 'CC', 110, 'MAS', 'SBC', DATE '2026-08-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000009, 8, 101, 'EC', 301, 'MAS', 'SBC', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000010, 125, 101, 'CC', 111, 'MAS', 'SBC', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000011, 45, 101, 'CC', 202, 'MAS', 'SBC', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000012, 69, 101, 'CC', 212, 'MAS', 'KPD', DATE '2026-08-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000013, 13, 101, 'EC', 305, 'MAS', 'SBC', DATE '2026-08-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000014, 47, 101, 'CC', 107, 'KPD', 'JTJ', DATE '2026-08-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000015, 1, 101, 'EC', 304, 'MAS', 'SBC', DATE '2026-08-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000016, 110, 101, 'CC', 204, 'MAS', 'SBC', DATE '2026-08-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000017, 39, 101, 'EC', 306, 'MAS', 'SBC', DATE '2026-08-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000018, 86, 101, 'CC', 101, 'MAS', 'SBC', DATE '2026-08-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000019, 3, 101, 'CC', 105, 'JTJ', 'SBC', DATE '2026-08-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000020, 133, 101, 'EC', 308, 'KPD', 'JTJ', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000021, 14, 101, 'EC', 303, 'MAS', 'SBC', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000022, 6, 101, 'CC', 102, 'MAS', 'SBC', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000023, 19, 101, 'CC', 211, 'MAS', 'SBC', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000024, 55, 101, 'CC', 201, 'MAS', 'SBC', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000025, 15, 101, 'CC', 108, 'MAS', 'JTJ', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000026, 145, 101, 'CC', 209, 'MAS', 'SBC', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000027, 31, 101, 'CC', 104, 'KPD', 'JTJ', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000028, 80, 101, 'CC', 109, 'MAS', 'SBC', DATE '2026-09-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000029, 62, 101, 'CC', 106, 'MAS', 'SBC', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000030, 142, 101, 'EC', 307, 'MAS', 'JTJ', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000031, 117, 101, 'CC', 203, 'MAS', 'SBC', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000032, 20, 101, 'EC', 302, 'MAS', 'SBC', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000033, 87, 101, 'CC', 210, 'MAS', 'SBC', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000034, 7, 101, 'CC', NULL, 'MAS', 'SBC', DATE '2026-09-14', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000035, 135, 101, 'CC', NULL, 'MAS', 'SBC', DATE '2026-09-14', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000036, 136, 101, 'CC', NULL, 'MAS', 'SBC', DATE '2026-09-17', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000037, 102, 102, 'EC', 306, 'MAS', 'SBC', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000038, 128, 102, 'EC', 308, 'MAS', 'SBC', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000039, 12, 102, 'CC', 110, 'KPD', 'SBC', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000040, 41, 102, 'CC', 208, 'MAS', 'SBC', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000041, 46, 102, 'CC', 204, 'MAS', 'SBC', DATE '2026-08-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000042, 112, 102, 'CC', 203, 'MAS', 'SBC', DATE '2026-08-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000043, 63, 102, 'CC', 105, 'MAS', 'KPD', DATE '2026-08-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000044, 4, 102, 'CC', 104, 'MAS', 'SBC', DATE '2026-08-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000045, 40, 102, 'EC', 304, 'MAS', 'SBC', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000046, 117, 102, 'CC', 206, 'MAS', 'SBC', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000047, 129, 102, 'CC', 210, 'MAS', 'JTJ', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000048, 16, 102, 'EC', 302, 'MAS', 'KPD', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000049, 19, 102, 'CC', 111, 'MAS', 'SBC', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000050, 133, 102, 'CC', 205, 'JTJ', 'SBC', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000051, 145, 102, 'CC', 109, 'JTJ', 'SBC', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000052, 3, 102, 'CC', 102, 'MAS', 'SBC', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000053, 6, 102, 'CC', 108, 'MAS', 'SBC', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000054, 89, 102, 'CC', 112, 'MAS', 'KPD', DATE '2026-09-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000055, 110, 102, 'CC', 101, 'KPD', 'JTJ', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000056, 141, 102, 'EC', 305, 'KPD', 'JTJ', DATE '2026-09-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000057, 135, 102, 'CC', 202, 'MAS', 'SBC', DATE '2026-09-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000058, 136, 102, 'CC', 107, 'MAS', 'KPD', DATE '2026-09-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000059, 126, 102, 'CC', 211, 'MAS', 'SBC', DATE '2026-09-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000060, 99, 102, 'CC', 212, 'MAS', 'SBC', DATE '2026-09-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000061, 31, 102, 'CC', NULL, 'JTJ', 'SBC', DATE '2026-09-23', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000062, 97, 102, 'CC', 209, 'MAS', 'SBC', DATE '2026-09-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000063, 53, 102, 'CC', 103, 'JTJ', 'SBC', DATE '2026-09-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000064, 103, 102, 'CC', 106, 'MAS', 'SBC', DATE '2026-09-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000065, 150, 102, 'CC', 201, 'MAS', 'SBC', DATE '2026-09-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000066, 14, 102, 'EC', 307, 'MAS', 'SBC', DATE '2026-09-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000067, 15, 102, 'EC', 303, 'MAS', 'SBC', DATE '2026-10-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000068, 25, 102, 'CC', 207, 'KPD', 'SBC', DATE '2026-10-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000069, 81, 102, 'CC', NULL, 'MAS', 'SBC', DATE '2026-10-02', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000070, 74, 102, 'CC', NULL, 'MAS', 'SBC', DATE '2026-10-03', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000071, 21, 103, 'CC', 101, 'MAS', 'SBC', DATE '2026-09-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000072, 63, 103, 'CC', 109, 'KPD', 'SBC', DATE '2026-09-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000073, 117, 103, 'EC', 307, 'MAS', 'SBC', DATE '2026-09-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000074, 5, 103, 'CC', 207, 'KPD', 'SBC', DATE '2026-09-10', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000075, 12, 103, 'CC', 102, 'MAS', 'SBC', DATE '2026-09-10', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000076, 131, 103, 'CC', 110, 'KPD', 'JTJ', DATE '2026-09-13', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000077, 81, 103, 'CC', 107, 'MAS', 'SBC', DATE '2026-09-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000078, 3, 103, 'CC', 210, 'MAS', 'SBC', DATE '2026-09-20', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000079, 135, 103, 'CC', 111, 'MAS', 'SBC', DATE '2026-09-21', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000080, 109, 103, 'EC', 308, 'MAS', 'SBC', DATE '2026-09-21', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000081, 1, 103, 'CC', 212, 'MAS', 'SBC', DATE '2026-09-22', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000082, 141, 103, 'EC', 304, 'MAS', 'SBC', DATE '2026-09-24', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000083, 10, 103, 'CC', 112, 'MAS', 'SBC', DATE '2026-09-24', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000084, 85, 103, 'CC', 205, 'MAS', 'SBC', DATE '2026-09-24', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000085, 143, 103, 'CC', 104, 'MAS', 'SBC', DATE '2026-09-26', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000086, 8, 103, 'EC', 301, 'KPD', 'SBC', DATE '2026-09-28', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000087, 76, 103, 'EC', 305, 'MAS', 'SBC', DATE '2026-09-30', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000088, 54, 103, 'CC', 106, 'JTJ', 'SBC', DATE '2026-10-01', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000089, 93, 103, 'CC', 209, 'MAS', 'SBC', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000090, 86, 103, 'CC', 103, 'MAS', 'SBC', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000091, 75, 103, 'CC', 201, 'MAS', 'SBC', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000092, 70, 103, 'CC', 203, 'JTJ', 'SBC', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000093, 13, 103, 'EC', 303, 'MAS', 'KPD', DATE '2026-10-05', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000094, 102, 103, 'CC', 202, 'MAS', 'SBC', DATE '2026-10-05', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000095, 118, 103, 'CC', 211, 'MAS', 'SBC', DATE '2026-10-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000096, 78, 103, 'CC', 108, 'MAS', 'SBC', DATE '2026-10-10', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000097, 77, 103, 'EC', 302, 'MAS', 'SBC', DATE '2026-10-11', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000098, 2, 103, 'CC', 105, 'MAS', 'KPD', DATE '2026-10-14', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000099, 92, 103, 'CC', 208, 'MAS', 'SBC', DATE '2026-10-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000100, 64, 103, 'CC', 206, 'MAS', 'SBC', DATE '2026-10-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000101, 23, 103, 'CC', NULL, 'MAS', 'SBC', DATE '2026-10-17', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000102, 99, 103, 'CC', NULL, 'MAS', 'KPD', DATE '2026-10-18', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000103, 42, 104, 'CC', 604, 'MAS', 'SBC', DATE '2026-08-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000104, 99, 104, 'CC', 409, 'MAS', 'SBC', DATE '2026-08-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000105, 3, 104, 'CC', 512, 'MAS', 'SBC', DATE '2026-08-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000106, 100, 104, 'CC', 404, 'MAS', 'SBC', DATE '2026-08-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000107, 43, 104, 'CC', 510, 'MAS', 'SBC', DATE '2026-08-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000108, 104, 104, 'CC', 402, 'MAS', 'SBC', DATE '2026-08-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000109, 140, 104, 'CC', NULL, 'MAS', 'SBC', DATE '2026-08-15', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000110, 101, 104, 'CC', 411, 'MAS', 'SBC', DATE '2026-08-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000111, 110, 104, 'CC', 507, 'MAS', 'SBC', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000112, 135, 104, 'CC', 410, 'JTJ', 'SBC', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000113, 36, 104, 'CC', 506, 'MAS', 'SBC', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000114, 89, 104, 'CC', 509, 'MAS', 'SBC', DATE '2026-08-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000115, 8, 104, 'CC', 607, 'MAS', 'SBC', DATE '2026-08-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000116, 27, 104, 'CC', 612, 'MAS', 'JTJ', DATE '2026-08-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000117, 58, 104, 'CC', 601, 'MAS', 'SBC', DATE '2026-08-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000118, 41, 104, 'CC', 501, 'MAS', 'SBC', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000119, 5, 104, 'CC', 401, 'KPD', 'JTJ', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000120, 14, 104, 'CC', 609, 'MAS', 'SBC', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000121, 19, 104, 'CC', 603, 'MAS', 'SBC', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000122, 35, 104, 'CC', 503, 'MAS', 'SBC', DATE '2026-09-10', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000123, 85, 104, 'CC', 511, 'MAS', 'SBC', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000124, 149, 104, 'CC', 505, 'MAS', 'SBC', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000125, 116, 104, 'CC', 403, 'MAS', 'SBC', DATE '2026-09-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000126, 23, 104, 'CC', 610, 'MAS', 'SBC', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000127, 134, 104, 'CC', 508, 'KPD', 'SBC', DATE '2026-09-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000128, 122, 105, 'CC', 602, 'MAS', 'SBC', DATE '2026-08-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000129, 18, 105, 'CC', 607, 'MAS', 'SBC', DATE '2026-08-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000130, 120, 105, 'CC', 407, 'KPD', 'SBC', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000131, 135, 105, 'CC', 409, 'MAS', 'SBC', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000132, 1, 105, 'CC', 502, 'MAS', 'SBC', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000133, 22, 105, 'CC', 401, 'MAS', 'SBC', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000134, 32, 105, 'CC', 604, 'MAS', 'SBC', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000135, 68, 105, 'CC', 609, 'MAS', 'SBC', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000136, 7, 105, 'CC', NULL, 'MAS', 'SBC', DATE '2026-09-10', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000137, 25, 105, 'CC', 503, 'MAS', 'SBC', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000138, 142, 105, 'CC', 505, 'MAS', 'KPD', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000139, 89, 105, 'CC', 611, 'MAS', 'SBC', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000140, 91, 105, 'CC', 408, 'MAS', 'SBC', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000141, 96, 105, 'CC', 411, 'MAS', 'SBC', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000142, 106, 105, 'CC', 610, 'MAS', 'SBC', DATE '2026-09-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000143, 126, 105, 'CC', 403, 'MAS', 'SBC', DATE '2026-09-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000144, 148, 105, 'CC', 511, 'MAS', 'SBC', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000145, 8, 105, 'CC', 501, 'JTJ', 'SBC', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000146, 121, 105, 'CC', 606, 'KPD', 'SBC', DATE '2026-09-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000147, 74, 105, 'CC', 601, 'MAS', 'SBC', DATE '2026-09-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000148, 5, 105, 'CC', 508, 'KPD', 'SBC', DATE '2026-09-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000149, 141, 105, 'CC', 507, 'MAS', 'SBC', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000150, 147, 105, 'CC', 504, 'MAS', 'SBC', DATE '2026-10-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000151, 84, 105, 'CC', 605, 'MAS', 'SBC', DATE '2026-10-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000152, 119, 106, 'CC', 403, 'MAS', 'SBC', DATE '2026-09-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000153, 127, 106, 'CC', 406, 'MAS', 'JTJ', DATE '2026-09-11', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000154, 10, 106, 'CC', 605, 'MAS', 'SBC', DATE '2026-09-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000155, 79, 106, 'CC', 612, 'MAS', 'SBC', DATE '2026-09-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000156, 59, 106, 'CC', 501, 'MAS', 'SBC', DATE '2026-09-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000157, 15, 106, 'CC', 402, 'MAS', 'SBC', DATE '2026-09-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000158, 7, 106, 'CC', 510, 'MAS', 'SBC', DATE '2026-09-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000159, 78, 106, 'CC', 603, 'JTJ', 'SBC', DATE '2026-09-20', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000160, 77, 106, 'CC', 608, 'MAS', 'SBC', DATE '2026-09-22', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000161, 3, 106, 'CC', 503, 'MAS', 'SBC', DATE '2026-09-23', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000162, 61, 106, 'CC', 512, 'MAS', 'SBC', DATE '2026-09-23', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000163, 98, 106, 'CC', 405, 'MAS', 'SBC', DATE '2026-09-24', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000164, 39, 106, 'CC', 507, 'MAS', 'SBC', DATE '2026-09-26', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000165, 137, 106, 'CC', 508, 'KPD', 'SBC', DATE '2026-09-26', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000166, 146, 106, 'CC', 409, 'MAS', 'SBC', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000167, 32, 106, 'CC', 505, 'JTJ', 'SBC', DATE '2026-09-28', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000168, 136, 106, 'CC', 601, 'MAS', 'SBC', DATE '2026-09-29', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000169, 104, 106, 'CC', 408, 'MAS', 'SBC', DATE '2026-10-01', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000170, 70, 106, 'CC', 411, 'MAS', 'SBC', DATE '2026-10-07', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000171, 105, 106, 'CC', 407, 'MAS', 'SBC', DATE '2026-10-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000172, 116, 106, 'CC', 401, 'MAS', 'JTJ', DATE '2026-10-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000173, 9, 106, 'CC', 607, 'MAS', 'SBC', DATE '2026-10-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000174, 102, 107, 'EC', 901, 'MAS', 'SBC', DATE '2026-08-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000175, 91, 107, 'CC', NULL, 'MAS', 'SBC', DATE '2026-08-11', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000176, 88, 107, 'EC', 905, 'MAS', 'SBC', DATE '2026-08-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000177, 84, 107, 'CC', 809, 'JTJ', 'SBC', DATE '2026-08-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000178, 19, 107, 'EC', 908, 'JTJ', 'SBC', DATE '2026-08-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000179, 38, 107, 'CC', 704, 'MAS', 'SBC', DATE '2026-08-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000180, 115, 107, 'CC', 702, 'MAS', 'SBC', DATE '2026-08-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000181, 35, 107, 'CC', 706, 'MAS', 'SBC', DATE '2026-08-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000182, 15, 107, 'CC', 708, 'JTJ', 'SBC', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000183, 41, 107, 'CC', NULL, 'KPD', 'SBC', DATE '2026-08-20', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000184, 18, 107, 'EC', 907, 'MAS', 'SBC', DATE '2026-08-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000185, 23, 107, 'CC', 806, 'MAS', 'SBC', DATE '2026-08-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000186, 82, 107, 'CC', 705, 'MAS', 'SBC', DATE '2026-08-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000187, 12, 107, 'EC', 903, 'MAS', 'SBC', DATE '2026-08-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000188, 37, 107, 'CC', 701, 'MAS', 'SBC', DATE '2026-08-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000189, 1, 107, 'CC', 803, 'MAS', 'SBC', DATE '2026-08-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000190, 79, 107, 'CC', 703, 'MAS', 'SBC', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000191, 74, 107, 'EC', 902, 'MAS', 'SBC', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000192, 135, 107, 'CC', 710, 'MAS', 'SBC', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000193, 3, 107, 'CC', 712, 'MAS', 'SBC', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000194, 14, 107, 'CC', NULL, 'MAS', 'SBC', DATE '2026-09-02', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000195, 133, 107, 'CC', 807, 'MAS', 'SBC', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000196, 139, 107, 'CC', 810, 'MAS', 'SBC', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000197, 125, 107, 'CC', 707, 'MAS', 'SBC', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000198, 118, 107, 'EC', 904, 'MAS', 'SBC', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000199, 33, 107, 'CC', 812, 'MAS', 'SBC', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000200, 104, 107, 'CC', 811, 'MAS', 'SBC', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000201, 7, 107, 'CC', NULL, 'KPD', 'JTJ', DATE '2026-09-08', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000202, 105, 107, 'CC', 709, 'MAS', 'SBC', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000203, 40, 107, 'CC', 802, 'MAS', 'SBC', DATE '2026-09-10', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000204, 9, 107, 'CC', 801, 'MAS', 'SBC', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000205, 31, 107, 'CC', 804, 'MAS', 'SBC', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000206, 51, 107, 'EC', 906, 'MAS', 'SBC', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000207, 117, 107, 'CC', 805, 'MAS', 'SBC', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000208, 64, 107, 'CC', 808, 'MAS', 'SBC', DATE '2026-09-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000209, 42, 107, 'CC', 711, 'MAS', 'SBC', DATE '2026-09-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000210, 4, 107, 'EC', NULL, 'MAS', 'JTJ', DATE '2026-09-17', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000211, 66, 107, 'CC', NULL, 'MAS', 'SBC', DATE '2026-09-17', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000212, 32, 107, 'CC', NULL, 'MAS', 'SBC', DATE '2026-09-19', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000213, 134, 108, 'CC', 704, 'MAS', 'SBC', DATE '2026-08-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000214, 138, 108, 'CC', 706, 'MAS', 'SBC', DATE '2026-08-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000215, 4, 108, 'CC', 709, 'MAS', 'SBC', DATE '2026-08-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000216, 32, 108, 'EC', 902, 'MAS', 'SBC', DATE '2026-08-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000217, 45, 108, 'CC', NULL, 'MAS', 'SBC', DATE '2026-08-28', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000218, 9, 108, 'CC', 802, 'JTJ', 'SBC', DATE '2026-08-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000219, 8, 108, 'CC', 710, 'MAS', 'JTJ', DATE '2026-08-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000220, 5, 108, 'CC', NULL, 'MAS', 'SBC', DATE '2026-08-31', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000221, 131, 108, 'CC', 701, 'MAS', 'SBC', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000222, 13, 108, 'CC', 711, 'MAS', 'SBC', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000223, 96, 108, 'CC', 712, 'MAS', 'SBC', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000224, 61, 108, 'CC', 804, 'MAS', 'SBC', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000225, 43, 108, 'CC', 807, 'JTJ', 'SBC', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000226, 148, 108, 'EC', 903, 'KPD', 'SBC', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000227, 116, 108, 'CC', 702, 'MAS', 'SBC', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000228, 93, 108, 'CC', 812, 'MAS', 'SBC', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000229, 89, 108, 'CC', 705, 'MAS', 'SBC', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000230, 18, 108, 'CC', 805, 'MAS', 'SBC', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000231, 98, 108, 'CC', 808, 'MAS', 'SBC', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000232, 39, 108, 'EC', 907, 'MAS', 'SBC', DATE '2026-09-10', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000233, 65, 108, 'CC', 810, 'MAS', 'SBC', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000234, 31, 108, 'EC', 901, 'MAS', 'SBC', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000235, 60, 108, 'CC', 803, 'JTJ', 'SBC', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000236, 92, 108, 'CC', 811, 'MAS', 'SBC', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000237, 23, 108, 'CC', NULL, 'MAS', 'SBC', DATE '2026-09-14', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000238, 50, 108, 'CC', NULL, 'MAS', 'SBC', DATE '2026-09-14', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000239, 15, 108, 'CC', 708, 'MAS', 'SBC', DATE '2026-09-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000240, 108, 108, 'EC', 905, 'MAS', 'SBC', DATE '2026-09-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000241, 142, 108, 'EC', 908, 'MAS', 'SBC', DATE '2026-09-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000242, 121, 108, 'CC', 806, 'KPD', 'SBC', DATE '2026-09-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000243, 42, 108, 'CC', NULL, 'KPD', 'JTJ', DATE '2026-09-26', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000244, 7, 108, 'CC', 703, 'MAS', 'SBC', DATE '2026-09-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000245, 59, 108, 'EC', 904, 'KPD', 'SBC', DATE '2026-09-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000246, 100, 108, 'CC', 707, 'MAS', 'SBC', DATE '2026-09-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000247, 6, 108, 'CC', 801, 'MAS', 'SBC', DATE '2026-10-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000248, 28, 108, 'CC', 809, 'MAS', 'SBC', DATE '2026-10-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000249, 54, 108, 'CC', NULL, 'MAS', 'SBC', DATE '2026-10-04', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000250, 58, 108, 'CC', NULL, 'MAS', 'SBC', DATE '2026-10-04', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000251, 42, 109, 'EC', 906, 'MAS', 'SBC', DATE '2026-09-11', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000252, 7, 109, 'CC', NULL, 'MAS', 'KPD', DATE '2026-09-11', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000253, 72, 109, 'CC', 811, 'MAS', 'SBC', DATE '2026-09-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000254, 147, 109, 'EC', 904, 'MAS', 'KPD', DATE '2026-09-13', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000255, 103, 109, 'CC', 812, 'MAS', 'KPD', DATE '2026-09-13', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000256, 31, 109, 'CC', 808, 'MAS', 'SBC', DATE '2026-09-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000257, 14, 109, 'CC', 707, 'MAS', 'SBC', DATE '2026-09-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000258, 47, 109, 'EC', NULL, 'MAS', 'SBC', DATE '2026-09-18', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000259, 43, 109, 'CC', 701, 'MAS', 'SBC', DATE '2026-09-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000260, 138, 109, 'CC', 807, 'MAS', 'SBC', DATE '2026-09-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000261, 24, 109, 'EC', 901, 'MAS', 'SBC', DATE '2026-09-21', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000262, 83, 109, 'CC', 803, 'MAS', 'SBC', DATE '2026-09-22', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000263, 120, 109, 'CC', 705, 'MAS', 'SBC', DATE '2026-09-22', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000264, 137, 109, 'EC', 905, 'MAS', 'SBC', DATE '2026-09-23', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000265, 23, 109, 'EC', NULL, 'MAS', 'SBC', DATE '2026-09-24', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000266, 129, 109, 'EC', 907, 'MAS', 'SBC', DATE '2026-09-25', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000267, 9, 109, 'CC', 802, 'MAS', 'SBC', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000268, 113, 109, 'CC', 804, 'MAS', 'SBC', DATE '2026-09-28', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000269, 5, 109, 'CC', 702, 'MAS', 'JTJ', DATE '2026-09-29', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000270, 70, 109, 'CC', 711, 'MAS', 'SBC', DATE '2026-10-01', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000271, 65, 109, 'CC', 704, 'MAS', 'JTJ', DATE '2026-10-01', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000272, 4, 109, 'CC', 703, 'MAS', 'SBC', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000273, 10, 109, 'CC', 712, 'MAS', 'SBC', DATE '2026-10-04', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000274, 64, 109, 'CC', 708, 'MAS', 'SBC', DATE '2026-10-04', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000275, 128, 109, 'EC', 902, 'KPD', 'SBC', DATE '2026-10-06', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000276, 104, 109, 'EC', 908, 'MAS', 'SBC', DATE '2026-10-08', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000277, 146, 109, 'CC', 810, 'MAS', 'SBC', DATE '2026-10-08', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000278, 6, 109, 'CC', 805, 'MAS', 'SBC', DATE '2026-10-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000279, 15, 109, 'CC', NULL, 'MAS', 'SBC', DATE '2026-10-11', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000280, 84, 109, 'CC', 809, 'MAS', 'SBC', DATE '2026-10-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000281, 61, 109, 'CC', 801, 'MAS', 'SBC', DATE '2026-10-13', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000282, 56, 109, 'CC', 710, 'MAS', 'SBC', DATE '2026-10-14', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000283, 19, 109, 'CC', 706, 'MAS', 'SBC', DATE '2026-10-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000284, 3, 109, 'CC', 806, 'MAS', 'SBC', DATE '2026-10-17', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000285, 73, 109, 'CC', NULL, 'MAS', 'KPD', DATE '2026-10-17', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000286, 88, 110, 'CC', 1102, 'MAS', 'MDU', DATE '2026-08-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000287, 110, 110, 'CC', 1203, 'MAS', 'MDU', DATE '2026-08-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000288, 139, 110, 'CC', 1103, 'MAS', 'MDU', DATE '2026-08-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000289, 27, 110, 'CC', 1210, 'MAS', 'MDU', DATE '2026-08-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000290, 102, 110, 'CC', 1206, 'MAS', 'MDU', DATE '2026-08-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000291, 144, 110, 'CC', 1011, 'MAS', 'MDU', DATE '2026-08-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000292, 87, 110, 'CC', 1004, 'MAS', 'MDU', DATE '2026-08-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000293, 7, 110, 'CC', NULL, 'MAS', 'MDU', DATE '2026-08-21', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000294, 30, 110, 'CC', 1205, 'MAS', 'MDU', DATE '2026-08-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000295, 8, 110, 'CC', 1204, 'MAS', 'MDU', DATE '2026-08-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000296, 5, 110, 'CC', 1006, 'MAS', 'MDU', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000297, 36, 110, 'CC', 1008, 'MAS', 'MDU', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000298, 23, 110, 'CC', 1108, 'MAS', 'MDU', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000299, 80, 110, 'CC', 1111, 'MAS', 'MDU', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000300, 116, 110, 'CC', 1101, 'MAS', 'MDU', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000301, 130, 110, 'CC', 1112, 'MAS', 'MDU', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000302, 2, 110, 'CC', 1209, 'MAS', 'MDU', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000303, 124, 110, 'CC', 1211, 'MAS', 'MDU', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000304, 70, 110, 'CC', 1003, 'MAS', 'MDU', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000305, 120, 110, 'CC', 1202, 'MAS', 'MDU', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000306, 25, 110, 'CC', 1109, 'MAS', 'MDU', DATE '2026-09-10', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000307, 3, 110, 'CC', 1105, 'MAS', 'MDU', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000308, 112, 110, 'CC', 1009, 'MAS', 'MDU', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000309, 1, 110, 'CC', 1201, 'MAS', 'MDU', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000310, 37, 110, 'CC', 1002, 'MAS', 'MDU', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000311, 61, 110, 'CC', 1207, 'MAS', 'MDU', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000312, 45, 110, 'CC', 1012, 'MAS', 'DG', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000313, 68, 110, 'CC', 1005, 'MAS', 'MDU', DATE '2026-09-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000314, 91, 110, 'CC', 1212, 'MAS', 'MDU', DATE '2026-09-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000315, 128, 110, 'CC', 1010, 'MAS', 'VM', DATE '2026-09-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000316, 107, 110, 'CC', 1007, 'MAS', 'MDU', DATE '2026-09-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000317, 79, 110, 'CC', 1001, 'MAS', 'MDU', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000318, 145, 111, 'CC', 1008, 'MAS', 'MDU', DATE '2026-08-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000319, 59, 111, 'CC', 1206, 'MAS', 'MDU', DATE '2026-08-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000320, 52, 111, 'CC', 1209, 'MAS', 'MDU', DATE '2026-08-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000321, 74, 111, 'CC', 1107, 'MAS', 'MDU', DATE '2026-08-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000322, 14, 111, 'CC', 1207, 'MAS', 'MDU', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000323, 12, 111, 'CC', 1106, 'MAS', 'MDU', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000324, 125, 111, 'CC', 1101, 'MAS', 'DG', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000325, 144, 111, 'CC', NULL, 'MAS', 'MDU', DATE '2026-08-31', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000326, 36, 111, 'CC', 1109, 'MAS', 'MDU', DATE '2026-09-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000327, 149, 111, 'CC', 1003, 'DG', 'MDU', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000328, 43, 111, 'CC', 1102, 'MAS', 'MDU', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000329, 104, 111, 'CC', 1108, 'MAS', 'MDU', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000330, 106, 111, 'CC', 1006, 'MAS', 'MDU', DATE '2026-09-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000331, 28, 111, 'CC', 1202, 'MAS', 'MDU', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000332, 141, 111, 'CC', 1002, 'MAS', 'MDU', DATE '2026-09-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000333, 85, 111, 'CC', 1009, 'MAS', 'MDU', DATE '2026-09-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000334, 48, 111, 'CC', 1110, 'MAS', 'MDU', DATE '2026-09-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000335, 94, 111, 'CC', NULL, 'MAS', 'MDU', DATE '2026-09-19', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000336, 2, 111, 'CC', 1203, 'MAS', 'MDU', DATE '2026-09-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000337, 19, 111, 'CC', 1010, 'MAS', 'MDU', DATE '2026-09-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000338, 122, 111, 'CC', 1112, 'MAS', 'MDU', DATE '2026-09-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000339, 147, 111, 'CC', 1205, 'MAS', 'MDU', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000340, 25, 111, 'CC', 1111, 'MAS', 'MDU', DATE '2026-09-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000341, 102, 111, 'CC', 1103, 'TPJ', 'DG', DATE '2026-09-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000342, 142, 111, 'CC', 1004, 'TPJ', 'MDU', DATE '2026-09-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000343, 130, 111, 'CC', 1211, 'MAS', 'MDU', DATE '2026-09-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000344, 80, 111, 'CC', 1005, 'VM', 'DG', DATE '2026-10-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000345, 66, 111, 'CC', 1204, 'MAS', 'MDU', DATE '2026-10-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000346, 37, 111, 'CC', 1012, 'MAS', 'TPJ', DATE '2026-10-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000347, 105, 111, 'CC', 1104, 'MAS', 'MDU', DATE '2026-10-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000348, 3, 111, 'CC', 1208, 'DG', 'MDU', DATE '2026-10-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000349, 9, 111, 'CC', 1011, 'MAS', 'MDU', DATE '2026-10-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000350, 44, 112, 'CC', 1107, 'MAS', 'VM', DATE '2026-09-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000351, 32, 112, 'CC', 1011, 'MAS', 'MDU', DATE '2026-09-10', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000352, 6, 112, 'CC', 1009, 'MAS', 'MDU', DATE '2026-09-10', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000353, 40, 112, 'CC', 1209, 'MAS', 'MDU', DATE '2026-09-11', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000354, 45, 112, 'CC', 1001, 'DG', 'MDU', DATE '2026-09-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000355, 72, 112, 'CC', 1006, 'MAS', 'MDU', DATE '2026-09-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000356, 23, 112, 'CC', NULL, 'MAS', 'MDU', DATE '2026-09-15', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000357, 132, 112, 'CC', 1203, 'MAS', 'VM', DATE '2026-09-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000358, 94, 112, 'CC', 1201, 'MAS', 'MDU', DATE '2026-09-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000359, 30, 112, 'CC', 1205, 'TPJ', 'DG', DATE '2026-09-17', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000360, 57, 112, 'CC', 1101, 'MAS', 'MDU', DATE '2026-09-17', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000361, 68, 112, 'CC', 1112, 'MAS', 'MDU', DATE '2026-09-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000362, 113, 112, 'CC', 1003, 'MAS', 'VM', DATE '2026-09-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000363, 10, 112, 'CC', 1202, 'MAS', 'MDU', DATE '2026-09-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000364, 80, 112, 'CC', 1206, 'MAS', 'MDU', DATE '2026-09-26', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000365, 73, 112, 'CC', 1007, 'MAS', 'VM', DATE '2026-09-28', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000366, 88, 112, 'CC', 1111, 'MAS', 'MDU', DATE '2026-09-28', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000367, 13, 112, 'CC', 1108, 'TPJ', 'DG', DATE '2026-09-28', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000368, 7, 112, 'CC', 1110, 'MAS', 'MDU', DATE '2026-09-29', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000369, 31, 112, 'CC', 1211, 'MAS', 'MDU', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000370, 50, 112, 'CC', 1102, 'MAS', 'MDU', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000371, 1, 112, 'CC', 1204, 'MAS', 'VM', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000372, 18, 112, 'CC', 1010, 'MAS', 'MDU', DATE '2026-10-07', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000373, 87, 112, 'CC', 1207, 'MAS', 'MDU', DATE '2026-10-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000374, 144, 112, 'CC', 1109, 'MAS', 'MDU', DATE '2026-10-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000375, 34, 112, 'CC', 1103, 'TPJ', 'MDU', DATE '2026-10-11', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000376, 74, 112, 'CC', 1212, 'DG', 'MDU', DATE '2026-10-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000377, 109, 112, 'CC', 1106, 'MAS', 'MDU', DATE '2026-10-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000378, 104, 112, 'CC', 1105, 'DG', 'MDU', DATE '2026-10-17', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000379, 15, 113, '2A', 1603, 'MAS', 'MDU', DATE '2026-08-10', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000380, 88, 113, 'SL', 1412, 'MAS', 'MDU', DATE '2026-08-10', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000381, 25, 113, 'SL', 1410, 'MAS', 'MDU', DATE '2026-08-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000382, 118, 113, '3A', 1506, 'MAS', 'MDU', DATE '2026-08-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000383, 120, 113, '3A', 1504, 'MAS', 'MDU', DATE '2026-08-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000384, 80, 113, '3A', 1509, 'TPJ', 'DG', DATE '2026-08-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000385, 113, 113, '2A', 1601, 'MAS', 'MDU', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000386, 86, 113, 'SL', 1402, 'MAS', 'MDU', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000387, 68, 113, 'SL', 1301, 'MAS', 'MDU', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000388, 66, 113, '3A', 1503, 'VM', 'TPJ', DATE '2026-08-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000389, 109, 113, '3A', 1510, 'MAS', 'MDU', DATE '2026-08-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000390, 48, 113, '2A', 1605, 'MAS', 'MDU', DATE '2026-08-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000391, 63, 113, 'SL', 1312, 'DG', 'MDU', DATE '2026-08-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000392, 148, 113, 'SL', 1311, 'MAS', 'DG', DATE '2026-08-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000393, 8, 113, 'SL', 1302, 'MAS', 'MDU', DATE '2026-08-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000394, 144, 113, 'SL', 1310, 'DG', 'MDU', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000395, 49, 113, 'SL', 1404, 'MAS', 'MDU', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000396, 102, 113, 'SL', 1306, 'MAS', 'MDU', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000397, 3, 113, '3A', 1501, 'MAS', 'MDU', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000398, 23, 113, 'SL', 1406, 'MAS', 'MDU', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000399, 84, 113, 'SL', 1305, 'MAS', 'MDU', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000400, 41, 113, 'SL', 1401, 'MAS', 'MDU', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000401, 124, 113, '2A', 1606, 'MAS', 'MDU', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000402, 85, 113, '3A', 1508, 'MAS', 'MDU', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000403, 100, 113, '2A', 1608, 'TPJ', 'DG', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000404, 147, 113, 'SL', 1408, 'MAS', 'DG', DATE '2026-09-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000405, 108, 113, '3A', 1502, 'MAS', 'MDU', DATE '2026-09-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000406, 121, 113, 'SL', 1407, 'MAS', 'MDU', DATE '2026-09-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000407, 105, 113, '2A', 1602, 'MAS', 'MDU', DATE '2026-09-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000408, 11, 113, 'SL', 1308, 'MAS', 'MDU', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000409, 24, 113, 'SL', 1309, 'MAS', 'MDU', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000410, 12, 113, 'SL', 1403, 'MAS', 'MDU', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000411, 106, 113, 'SL', 1409, 'MAS', 'MDU', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000412, 123, 113, 'SL', 1304, 'TPJ', 'MDU', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000413, 13, 113, '3A', 1505, 'MAS', 'MDU', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000414, 6, 113, '2A', 1607, 'MAS', 'MDU', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000415, 140, 113, 'SL', 1303, 'DG', 'MDU', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000416, 64, 113, 'SL', 1307, 'MAS', 'MDU', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000417, 59, 113, '3A', 1507, 'MAS', 'MDU', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000418, 142, 113, 'SL', 1411, 'MAS', 'MDU', DATE '2026-09-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000419, 70, 113, 'SL', 1405, 'MAS', 'MDU', DATE '2026-09-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000420, 44, 113, '2A', 1604, 'MAS', 'MDU', DATE '2026-09-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000421, 19, 113, 'SL', NULL, 'MAS', 'MDU', DATE '2026-09-23', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000422, 115, 113, 'SL', NULL, 'TPJ', 'MDU', DATE '2026-09-23', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000423, 103, 113, 'SL', NULL, 'MAS', 'MDU', DATE '2026-09-23', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000424, 31, 114, 'SL', 1310, 'MAS', 'MDU', DATE '2026-08-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000425, 73, 114, 'SL', 1308, 'MAS', 'MDU', DATE '2026-08-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000426, 8, 114, 'SL', 1305, 'MAS', 'MDU', DATE '2026-08-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000427, 26, 114, 'SL', 1401, 'MAS', 'MDU', DATE '2026-08-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000428, 3, 114, '3A', 1510, 'MAS', 'MDU', DATE '2026-08-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000429, 27, 114, '3A', 1503, 'MAS', 'MDU', DATE '2026-08-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000430, 38, 114, 'SL', 1405, 'MAS', 'MDU', DATE '2026-08-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000431, 7, 114, 'SL', 1404, 'MAS', 'MDU', DATE '2026-08-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000432, 133, 114, '3A', 1504, 'MAS', 'MDU', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000433, 9, 114, 'SL', 1303, 'MAS', 'MDU', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000434, 76, 114, 'SL', 1409, 'MAS', 'MDU', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000435, 44, 114, 'SL', 1412, 'MAS', 'MDU', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000436, 69, 114, 'SL', 1402, 'MAS', 'MDU', DATE '2026-09-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000437, 21, 114, 'SL', 1307, 'MAS', 'MDU', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000438, 110, 114, '3A', 1501, 'MAS', 'MDU', DATE '2026-09-10', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000439, 54, 114, 'SL', 1406, 'MAS', 'MDU', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000440, 23, 114, 'SL', NULL, 'MAS', 'MDU', DATE '2026-09-13', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000441, 118, 114, '2A', 1604, 'MAS', 'MDU', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000442, 84, 114, 'SL', 1411, 'DG', 'MDU', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000443, 139, 114, '2A', 1605, 'MAS', 'MDU', DATE '2026-09-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000444, 132, 114, 'SL', 1407, 'MAS', 'MDU', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000445, 22, 114, 'SL', 1301, 'VM', 'TPJ', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000446, 64, 114, '3A', 1507, 'VM', 'MDU', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000447, 34, 114, '2A', 1603, 'MAS', 'MDU', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000448, 49, 114, '2A', 1601, 'MAS', 'MDU', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000449, 140, 114, 'SL', 1309, 'MAS', 'MDU', DATE '2026-09-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000450, 4, 114, '2A', 1602, 'VM', 'MDU', DATE '2026-09-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000451, 55, 114, '3A', 1502, 'MAS', 'MDU', DATE '2026-09-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000452, 32, 114, 'SL', 1311, 'MAS', 'MDU', DATE '2026-09-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000453, 15, 114, 'SL', 1304, 'MAS', 'MDU', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000454, 86, 114, 'SL', 1306, 'DG', 'MDU', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000455, 82, 114, 'SL', 1312, 'MAS', 'MDU', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000456, 61, 114, '2A', 1607, 'DG', 'MDU', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000457, 113, 114, '2A', 1606, 'DG', 'MDU', DATE '2026-09-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000458, 13, 114, 'SL', 1403, 'DG', 'MDU', DATE '2026-09-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000459, 150, 114, 'SL', 1302, 'MAS', 'MDU', DATE '2026-09-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000460, 50, 114, '3A', 1506, 'MAS', 'TPJ', DATE '2026-09-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000461, 5, 114, '2A', 1608, 'VM', 'TPJ', DATE '2026-10-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000462, 6, 114, '3A', 1505, 'MAS', 'MDU', DATE '2026-10-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000463, 66, 114, '3A', 1509, 'MAS', 'MDU', DATE '2026-10-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000464, 43, 114, 'SL', 1410, 'MAS', 'MDU', DATE '2026-10-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000465, 116, 114, 'SL', 1408, 'TPJ', 'DG', DATE '2026-10-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000466, 144, 114, 'SL', NULL, 'MAS', 'MDU', DATE '2026-10-06', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000467, 39, 114, 'SL', NULL, 'MAS', 'MDU', DATE '2026-10-06', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000468, 85, 114, 'SL', NULL, 'MAS', 'MDU', DATE '2026-10-07', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000469, 146, 115, 'SL', 1406, 'MAS', 'MDU', DATE '2026-09-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000470, 5, 115, 'SL', 1404, 'MAS', 'MDU', DATE '2026-09-13', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000471, 26, 115, '3A', 1505, 'MAS', 'MDU', DATE '2026-09-14', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000472, 68, 115, 'SL', 1302, 'MAS', 'MDU', DATE '2026-09-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000473, 19, 115, 'SL', 1303, 'DG', 'MDU', DATE '2026-09-17', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000474, 114, 115, 'SL', 1409, 'VM', 'DG', DATE '2026-09-17', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000475, 87, 115, '3A', 1503, 'MAS', 'MDU', DATE '2026-09-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000476, 10, 115, 'SL', 1307, 'VM', 'DG', DATE '2026-09-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000477, 32, 115, 'SL', 1311, 'MAS', 'MDU', DATE '2026-09-21', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000478, 53, 115, 'SL', 1310, 'MAS', 'MDU', DATE '2026-09-22', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000479, 145, 115, 'SL', 1407, 'MAS', 'MDU', DATE '2026-09-22', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000480, 30, 115, '2A', 1603, 'MAS', 'MDU', DATE '2026-09-23', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000481, 91, 115, 'SL', 1412, 'MAS', 'MDU', DATE '2026-09-24', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000482, 77, 115, '2A', 1604, 'MAS', 'MDU', DATE '2026-09-25', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000483, 144, 115, '2A', 1607, 'MAS', 'DG', DATE '2026-09-26', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000484, 139, 115, '3A', 1510, 'MAS', 'MDU', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000485, 63, 115, '3A', 1507, 'VM', 'MDU', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000486, 93, 115, 'SL', 1304, 'MAS', 'MDU', DATE '2026-09-30', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000487, 120, 115, '3A', 1502, 'MAS', 'MDU', DATE '2026-10-01', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000488, 100, 115, '2A', 1602, 'MAS', 'MDU', DATE '2026-10-01', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000489, 21, 115, 'SL', 1312, 'TPJ', 'DG', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000490, 22, 115, '2A', 1608, 'MAS', 'MDU', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000491, 95, 115, 'SL', 1306, 'DG', 'MDU', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000492, 130, 115, '3A', 1504, 'VM', 'DG', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000493, 14, 115, '3A', 1508, 'MAS', 'MDU', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000494, 98, 115, '3A', 1501, 'MAS', 'TPJ', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000495, 31, 115, '3A', 1506, 'MAS', 'MDU', DATE '2026-10-04', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000496, 11, 115, 'SL', 1410, 'MAS', 'MDU', DATE '2026-10-05', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000497, 99, 115, 'SL', 1305, 'MAS', 'MDU', DATE '2026-10-05', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000498, 108, 115, 'SL', 1405, 'MAS', 'MDU', DATE '2026-10-05', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000499, 74, 115, '2A', 1601, 'MAS', 'MDU', DATE '2026-10-05', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000500, 7, 115, 'SL', 1402, 'MAS', 'MDU', DATE '2026-10-06', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000501, 73, 115, 'SL', 1401, 'MAS', 'MDU', DATE '2026-10-07', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000502, 18, 115, '3A', 1509, 'MAS', 'MDU', DATE '2026-10-07', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000503, 6, 115, 'SL', 1301, 'MAS', 'MDU', DATE '2026-10-08', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000504, 47, 115, 'SL', 1309, 'MAS', 'MDU', DATE '2026-10-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000505, 33, 115, 'SL', 1408, 'MAS', 'MDU', DATE '2026-10-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000506, 45, 115, 'SL', 1403, 'MAS', 'MDU', DATE '2026-10-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000507, 72, 115, '2A', 1606, 'MAS', 'MDU', DATE '2026-10-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000508, 80, 115, 'SL', NULL, 'MAS', 'MDU', DATE '2026-10-18', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000509, 149, 115, 'SL', NULL, 'DG', 'MDU', DATE '2026-10-18', 'WAITLIST');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000510, 17, 116, 'EC', 1905, 'TPJ', 'MDU', DATE '2026-08-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000511, 27, 116, 'CC', 1806, 'DG', 'MDU', DATE '2026-08-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000512, 50, 116, 'CC', 1701, 'MAS', 'MDU', DATE '2026-08-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000513, 21, 116, 'CC', 1708, 'MAS', 'MDU', DATE '2026-08-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000514, 124, 116, 'CC', 1710, 'MAS', 'MDU', DATE '2026-08-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000515, 45, 116, 'CC', 1711, 'MAS', 'MDU', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000516, 4, 116, 'CC', 1703, 'MAS', 'MDU', DATE '2026-08-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000517, 63, 116, 'EC', 1907, 'MAS', 'MDU', DATE '2026-08-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000518, 64, 116, 'CC', 1802, 'VM', 'DG', DATE '2026-08-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000519, 15, 116, 'CC', NULL, 'DG', 'MDU', DATE '2026-08-27', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000520, 62, 116, 'CC', 1709, 'MAS', 'MDU', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000521, 29, 116, 'CC', 1804, 'TPJ', 'DG', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000522, 5, 116, 'CC', 1812, 'MAS', 'MDU', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000523, 23, 116, 'CC', NULL, 'MAS', 'MDU', DATE '2026-09-15', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000524, 109, 116, 'EC', 1903, 'MAS', 'MDU', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000525, 2, 116, 'CC', 1707, 'MAS', 'MDU', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000526, 96, 116, 'EC', 1901, 'MAS', 'MDU', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000527, 41, 116, 'CC', 1702, 'MAS', 'MDU', DATE '2026-09-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000528, 6, 116, 'CC', 1811, 'MAS', 'MDU', DATE '2026-09-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000529, 23, 117, 'CC', 1802, 'MAS', 'MDU', DATE '2026-08-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000530, 15, 117, 'EC', NULL, 'MAS', 'MDU', DATE '2026-08-29', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000531, 50, 117, 'CC', 1711, 'MAS', 'MDU', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000532, 20, 117, 'CC', 1703, 'MAS', 'MDU', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000533, 30, 117, 'EC', 1907, 'MAS', 'MDU', DATE '2026-09-10', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000534, 112, 117, 'CC', 1812, 'MAS', 'MDU', DATE '2026-09-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000535, 84, 117, 'CC', 1803, 'MAS', 'MDU', DATE '2026-09-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000536, 37, 117, 'CC', 1705, 'MAS', 'MDU', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000537, 4, 117, 'CC', 1807, 'DG', 'MDU', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000538, 106, 117, 'CC', 1702, 'DG', 'MDU', DATE '2026-09-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000539, 11, 117, 'CC', 1710, 'MAS', 'MDU', DATE '2026-09-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000540, 132, 117, 'CC', 1704, 'MAS', 'MDU', DATE '2026-09-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000541, 147, 117, 'CC', 1811, 'MAS', 'MDU', DATE '2026-09-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000542, 107, 117, 'CC', 1810, 'MAS', 'MDU', DATE '2026-10-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000543, 108, 117, 'CC', 1709, 'MAS', 'MDU', DATE '2026-10-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000544, 86, 117, 'CC', 1706, 'MAS', 'MDU', DATE '2026-10-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000545, 145, 117, 'CC', 1808, 'MAS', 'MDU', DATE '2026-10-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000546, 16, 118, 'CC', 1805, 'MAS', 'MDU', DATE '2026-09-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000547, 136, 118, 'EC', 1903, 'MAS', 'MDU', DATE '2026-09-11', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000548, 57, 118, 'CC', 1712, 'MAS', 'MDU', DATE '2026-09-13', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000549, 56, 118, 'CC', 1708, 'MAS', 'MDU', DATE '2026-09-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000550, 17, 118, 'CC', 1701, 'MAS', 'MDU', DATE '2026-09-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000551, 37, 118, 'EC', 1906, 'MAS', 'MDU', DATE '2026-09-21', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000552, 38, 118, 'CC', 1811, 'MAS', 'MDU', DATE '2026-09-25', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000553, 127, 118, 'CC', 1803, 'TPJ', 'DG', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000554, 31, 118, 'CC', NULL, 'VM', 'MDU', DATE '2026-09-27', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000555, 35, 118, 'CC', 1804, 'MAS', 'MDU', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000556, 124, 118, 'EC', 1902, 'TPJ', 'DG', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000557, 9, 118, 'CC', 1710, 'MAS', 'MDU', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000558, 42, 118, 'CC', 1812, 'MAS', 'MDU', DATE '2026-10-08', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000559, 55, 118, 'CC', 1706, 'MAS', 'MDU', DATE '2026-10-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000560, 41, 118, 'CC', 1707, 'MAS', 'MDU', DATE '2026-10-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000561, 63, 119, 'EC', 2204, 'KPD', 'ED', DATE '2026-08-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000562, 67, 119, 'CC', 2107, 'MAS', 'CBE', DATE '2026-08-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000563, 8, 119, 'CC', NULL, 'MAS', 'CBE', DATE '2026-08-16', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000564, 9, 119, 'EC', 2203, 'KPD', 'ED', DATE '2026-08-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000565, 139, 119, 'CC', 2005, 'MAS', 'CBE', DATE '2026-08-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000566, 64, 119, 'CC', 2101, 'MAS', 'CBE', DATE '2026-08-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000567, 133, 119, 'CC', 2106, 'MAS', 'CBE', DATE '2026-08-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000568, 88, 119, 'CC', 2012, 'MAS', 'CBE', DATE '2026-08-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000569, 25, 119, 'CC', 2108, 'MAS', 'CBE', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000570, 75, 119, 'CC', 2006, 'MAS', 'CBE', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000571, 38, 119, 'CC', 2105, 'MAS', 'CBE', DATE '2026-08-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000572, 41, 119, 'CC', 2009, 'SA', 'ED', DATE '2026-08-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000573, 145, 119, 'CC', 2011, 'MAS', 'CBE', DATE '2026-08-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000574, 11, 119, 'CC', 2007, 'JTJ', 'SA', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000575, 62, 119, 'EC', 2208, 'MAS', 'CBE', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000576, 27, 119, 'EC', 2207, 'SA', 'CBE', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000577, 56, 119, 'CC', 2103, 'MAS', 'CBE', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000578, 15, 119, 'EC', 2201, 'MAS', 'CBE', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000579, 33, 119, 'CC', 2110, 'MAS', 'CBE', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000580, 19, 119, 'CC', 2002, 'MAS', 'CBE', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000581, 47, 119, 'CC', 2004, 'MAS', 'CBE', DATE '2026-09-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000582, 13, 119, 'CC', 2003, 'MAS', 'CBE', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000583, 142, 119, 'CC', 2104, 'MAS', 'CBE', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000584, 24, 119, 'EC', 2202, 'MAS', 'CBE', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000585, 81, 119, 'CC', 2001, 'MAS', 'CBE', DATE '2026-09-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000586, 6, 119, 'CC', 2008, 'MAS', 'CBE', DATE '2026-09-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000587, 73, 119, 'CC', 2109, 'MAS', 'CBE', DATE '2026-09-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000588, 51, 120, 'CC', 2009, 'SA', 'CBE', DATE '2026-08-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000589, 47, 120, 'CC', 2109, 'KPD', 'JTJ', DATE '2026-08-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000590, 15, 120, 'CC', NULL, 'JTJ', 'ED', DATE '2026-08-30', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000591, 95, 120, 'CC', 2103, 'MAS', 'CBE', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000592, 42, 120, 'EC', 2205, 'MAS', 'CBE', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000593, 3, 120, 'CC', 2112, 'MAS', 'CBE', DATE '2026-09-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000594, 54, 120, 'CC', 2107, 'MAS', 'CBE', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000595, 105, 120, 'EC', 2208, 'MAS', 'CBE', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000596, 60, 120, 'EC', 2204, 'MAS', 'CBE', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000597, 13, 120, 'CC', 2007, 'MAS', 'CBE', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000598, 10, 120, 'EC', 2202, 'MAS', 'CBE', DATE '2026-09-10', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000599, 19, 120, 'EC', 2203, 'MAS', 'CBE', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000600, 121, 120, 'CC', 2110, 'MAS', 'CBE', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000601, 109, 120, 'CC', 2105, 'ED', 'CBE', DATE '2026-09-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000602, 144, 120, 'CC', 2111, 'MAS', 'CBE', DATE '2026-09-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000603, 11, 120, 'CC', 2005, 'MAS', 'CBE', DATE '2026-09-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000604, 140, 120, 'CC', 2008, 'MAS', 'CBE', DATE '2026-09-23', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000605, 72, 120, 'EC', 2201, 'SA', 'CBE', DATE '2026-09-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000606, 20, 120, 'CC', 2012, 'MAS', 'CBE', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000607, 91, 120, 'CC', 2006, 'ED', 'CBE', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000608, 7, 120, 'CC', 2010, 'MAS', 'CBE', DATE '2026-09-27', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000609, 79, 120, 'CC', 2102, 'MAS', 'CBE', DATE '2026-09-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000610, 98, 120, 'CC', 2003, 'MAS', 'CBE', DATE '2026-09-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000611, 111, 120, 'CC', 2002, 'MAS', 'CBE', DATE '2026-09-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000612, 5, 120, 'CC', 2001, 'MAS', 'CBE', DATE '2026-10-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000613, 64, 120, 'CC', 2106, 'MAS', 'CBE', DATE '2026-10-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000614, 99, 121, 'CC', 2103, 'SA', 'CBE', DATE '2026-09-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000615, 73, 121, 'CC', 2005, 'MAS', 'CBE', DATE '2026-09-14', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000616, 144, 121, 'CC', 2002, 'MAS', 'CBE', DATE '2026-09-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000617, 134, 121, 'EC', 2206, 'MAS', 'CBE', DATE '2026-09-21', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000618, 31, 121, 'CC', NULL, 'MAS', 'CBE', DATE '2026-09-21', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000619, 42, 121, 'CC', 2112, 'ED', 'CBE', DATE '2026-09-25', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000620, 92, 121, 'EC', 2204, 'MAS', 'CBE', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000621, 83, 121, 'CC', 2012, 'MAS', 'CBE', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000622, 56, 121, 'EC', 2202, 'MAS', 'CBE', DATE '2026-09-30', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000623, 26, 121, 'CC', 2107, 'MAS', 'CBE', DATE '2026-10-04', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000624, 37, 121, 'CC', 2008, 'MAS', 'CBE', DATE '2026-10-04', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000625, 80, 121, 'CC', 2106, 'MAS', 'CBE', DATE '2026-10-06', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000626, 20, 121, 'CC', 2007, 'MAS', 'CBE', DATE '2026-10-06', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000627, 34, 121, 'CC', 2111, 'KPD', 'ED', DATE '2026-10-07', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000628, 40, 121, 'CC', 2006, 'MAS', 'CBE', DATE '2026-10-08', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000629, 91, 121, 'CC', 2001, 'MAS', 'CBE', DATE '2026-10-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000630, 138, 121, 'EC', 2207, 'MAS', 'CBE', DATE '2026-10-10', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000631, 30, 121, 'CC', 2110, 'MAS', 'CBE', DATE '2026-10-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000632, 100, 121, 'CC', 2105, 'MAS', 'CBE', DATE '2026-10-13', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000633, 6, 121, 'CC', 2101, 'JTJ', 'ED', DATE '2026-10-14', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000634, 35, 121, 'CC', 2102, 'MAS', 'CBE', DATE '2026-10-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000635, 5, 121, 'CC', 2004, 'MAS', 'CBE', DATE '2026-10-15', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000636, 67, 121, 'EC', 2201, 'ED', 'CBE', DATE '2026-10-17', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000637, 2, 121, 'EC', 2208, 'MAS', 'CBE', DATE '2026-10-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000638, 118, 121, 'CC', 2108, 'MAS', 'CBE', DATE '2026-10-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000639, 21, 122, 'SL', 2311, 'MAS', 'CBE', DATE '2026-08-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000640, 66, 122, 'SL', 2312, 'MAS', 'CBE', DATE '2026-08-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000641, 56, 122, '2A', 2601, 'MAS', 'CBE', DATE '2026-08-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000642, 112, 122, 'SL', 2411, 'MAS', 'CBE', DATE '2026-08-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000643, 62, 122, 'SL', 2408, 'MAS', 'CBE', DATE '2026-08-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000644, 4, 122, '2A', 2607, 'MAS', 'CBE', DATE '2026-08-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000645, 88, 122, '2A', 2605, 'MAS', 'CBE', DATE '2026-08-16', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000646, 39, 122, 'SL', 2404, 'MAS', 'CBE', DATE '2026-08-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000647, 44, 122, 'SL', 2401, 'SA', 'CBE', DATE '2026-08-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000648, 15, 122, 'SL', 2410, 'MAS', 'CBE', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000649, 26, 122, 'SL', 2308, 'SA', 'ED', DATE '2026-08-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000650, 126, 122, '2A', 2606, 'MAS', 'CBE', DATE '2026-08-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000651, 22, 122, 'SL', 2302, 'MAS', 'CBE', DATE '2026-08-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000652, 13, 122, '3A', 2502, 'MAS', 'CBE', DATE '2026-08-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000653, 83, 122, 'SL', 2412, 'MAS', 'CBE', DATE '2026-08-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000654, 120, 122, 'SL', 2304, 'MAS', 'CBE', DATE '2026-08-28', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000655, 97, 122, 'SL', 2409, 'MAS', 'CBE', DATE '2026-08-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000656, 3, 122, '2A', 2604, 'MAS', 'CBE', DATE '2026-09-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000657, 132, 122, 'SL', 2402, 'MAS', 'CBE', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000658, 33, 122, '1A', 2703, 'MAS', 'CBE', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000659, 74, 122, '2A', 2603, 'MAS', 'CBE', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000660, 40, 122, 'SL', 2405, 'MAS', 'CBE', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000661, 114, 122, '3A', 2503, 'MAS', 'CBE', DATE '2026-09-05', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000662, 8, 122, '3A', 2509, 'ED', 'CBE', DATE '2026-09-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000663, 36, 122, 'SL', 2403, 'MAS', 'CBE', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000664, 19, 122, 'SL', NULL, 'MAS', 'CBE', DATE '2026-09-13', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000665, 129, 122, '3A', 2504, 'MAS', 'CBE', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000666, 9, 122, 'SL', 2301, 'MAS', 'CBE', DATE '2026-09-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000667, 59, 122, '3A', 2507, 'MAS', 'CBE', DATE '2026-09-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000668, 35, 122, '2A', 2608, 'MAS', 'CBE', DATE '2026-09-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000669, 63, 123, '2A', 2603, 'MAS', 'CBE', DATE '2026-08-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000670, 70, 123, 'SL', 2412, 'MAS', 'CBE', DATE '2026-08-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000671, 52, 123, 'SL', 2311, 'SA', 'CBE', DATE '2026-08-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000672, 68, 123, 'SL', 2405, 'MAS', 'CBE', DATE '2026-08-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000673, 64, 123, '2A', 2606, 'MAS', 'CBE', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000674, 145, 123, 'SL', 2403, 'MAS', 'ED', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000675, 148, 123, 'SL', 2306, 'MAS', 'CBE', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000676, 23, 123, 'SL', NULL, 'MAS', 'CBE', DATE '2026-09-08', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000677, 17, 123, 'SL', 2411, 'MAS', 'CBE', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000678, 11, 123, 'SL', 2401, 'MAS', 'CBE', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000679, 88, 123, 'SL', 2302, 'MAS', 'CBE', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000680, 41, 123, 'SL', 2308, 'MAS', 'CBE', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000681, 22, 123, 'SL', 2406, 'MAS', 'CBE', DATE '2026-09-14', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000682, 10, 123, 'SL', 2312, 'MAS', 'CBE', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000683, 79, 123, '3A', 2501, 'MAS', 'CBE', DATE '2026-09-17', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000684, 102, 123, 'SL', 2410, 'MAS', 'CBE', DATE '2026-09-18', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000685, 29, 123, 'SL', 2305, 'MAS', 'CBE', DATE '2026-09-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000686, 115, 123, '2A', 2608, 'JTJ', 'ED', DATE '2026-09-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000687, 12, 123, '3A', 2508, 'JTJ', 'ED', DATE '2026-09-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000688, 111, 123, 'SL', 2402, 'MAS', 'CBE', DATE '2026-09-29', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000689, 19, 123, 'SL', 2409, 'MAS', 'CBE', DATE '2026-10-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000690, 37, 123, '3A', 2504, 'KPD', 'SA', DATE '2026-10-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000691, 76, 123, 'SL', 2309, 'MAS', 'CBE', DATE '2026-10-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000692, 78, 123, 'SL', 2407, 'MAS', 'CBE', DATE '2026-10-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000693, 51, 123, '3A', 2510, 'KPD', 'ED', DATE '2026-10-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000694, 15, 123, '1A', 2701, 'MAS', 'SA', DATE '2026-10-06', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000695, 42, 123, '1A', NULL, 'JTJ', 'ED', DATE '2026-10-06', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000696, 53, 123, '3A', 2502, 'MAS', 'CBE', DATE '2026-10-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000697, 6, 123, 'SL', 2310, 'KPD', 'SA', DATE '2026-10-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000698, 105, 124, '3A', 2506, 'MAS', 'CBE', DATE '2026-09-11', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000699, 134, 124, '3A', 2510, 'JTJ', 'SA', DATE '2026-09-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000700, 108, 124, 'SL', 2404, 'MAS', 'CBE', DATE '2026-09-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000701, 109, 124, '2A', 2601, 'MAS', 'CBE', DATE '2026-09-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000702, 85, 124, 'SL', 2303, 'MAS', 'CBE', DATE '2026-09-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000703, 116, 124, '1A', 2702, 'MAS', 'CBE', DATE '2026-09-19', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000704, 136, 124, 'SL', 2310, 'SA', 'ED', DATE '2026-09-20', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000705, 87, 124, '3A', 2504, 'MAS', 'SA', DATE '2026-09-21', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000706, 44, 124, '2A', 2608, 'MAS', 'CBE', DATE '2026-09-24', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000707, 8, 124, 'SL', 2306, 'SA', 'CBE', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000708, 149, 124, 'SL', 2410, 'ED', 'CBE', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000709, 93, 124, '2A', 2602, 'MAS', 'CBE', DATE '2026-09-27', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000710, 30, 124, '2A', 2604, 'MAS', 'CBE', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000711, 102, 124, 'SL', 2406, 'MAS', 'CBE', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000712, 122, 124, 'SL', 2309, 'MAS', 'CBE', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000713, 12, 124, '1A', 2704, 'MAS', 'CBE', DATE '2026-10-03', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000714, 2, 124, '2A', 2606, 'MAS', 'CBE', DATE '2026-10-06', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000715, 11, 124, 'SL', 2407, 'MAS', 'CBE', DATE '2026-10-08', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000716, 141, 124, 'SL', 2408, 'MAS', 'CBE', DATE '2026-10-10', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000717, 17, 124, 'SL', 2305, 'MAS', 'CBE', DATE '2026-10-11', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000718, 148, 124, 'SL', 2405, 'MAS', 'CBE', DATE '2026-10-12', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000719, 123, 124, '1A', 2701, 'MAS', 'CBE', DATE '2026-10-13', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000720, 86, 124, 'SL', 2402, 'MAS', 'CBE', DATE '2026-10-13', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000721, 121, 124, 'SL', 2409, 'MAS', 'CBE', DATE '2026-10-14', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000722, 125, 124, '2A', 2607, 'KPD', 'CBE', DATE '2026-10-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000723, 106, 124, '3A', 2501, 'MAS', 'CBE', DATE '2026-10-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000724, 23, 125, 'CC', NULL, 'SBC', 'ERS', DATE '2026-08-15', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000725, 9, 125, 'EC', 3004, 'SBC', 'ERS', DATE '2026-08-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000726, 126, 125, 'EC', 3007, 'SBC', 'ERS', DATE '2026-08-19', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000727, 86, 125, 'CC', 2809, 'SBC', 'ERS', DATE '2026-08-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000728, 1, 125, 'CC', 2912, 'SBC', 'ERS', DATE '2026-08-24', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000729, 107, 125, 'CC', 2903, 'SBC', 'ERS', DATE '2026-08-31', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000730, 148, 125, 'CC', 2802, 'ED', 'ERS', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000731, 15, 125, 'CC', 2801, 'SBC', 'ERS', DATE '2026-09-03', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000732, 31, 125, 'CC', 2812, 'SBC', 'ERS', DATE '2026-09-04', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000733, 110, 125, 'EC', 3001, 'SBC', 'ERS', DATE '2026-09-08', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000734, 73, 125, 'CC', 2910, 'SBC', 'ERS', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000735, 95, 125, 'CC', 2902, 'ED', 'ERS', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000736, 98, 125, 'CC', 2810, 'SBC', 'ERS', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000737, 94, 125, 'CC', 2907, 'SBC', 'ERS', DATE '2026-09-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000738, 36, 125, 'EC', 3006, 'SBC', 'ERS', DATE '2026-09-15', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000739, 71, 125, 'CC', 2807, 'ED', 'CBE', DATE '2026-09-20', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000740, 13, 125, 'CC', 2905, 'SBC', 'ERS', DATE '2026-09-21', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000741, 7, 126, 'CC', 2801, 'ED', 'CBE', DATE '2026-09-02', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000742, 89, 126, 'CC', 2902, 'SBC', 'ERS', DATE '2026-09-07', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000743, 12, 126, 'CC', 2911, 'SBC', 'ERS', DATE '2026-09-09', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000744, 17, 126, 'EC', 3008, 'SBC', 'ERS', DATE '2026-09-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000745, 112, 126, 'CC', 2804, 'PGT', 'ERS', DATE '2026-09-12', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000746, 57, 126, 'CC', 2912, 'SBC', 'ERS', DATE '2026-09-13', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000747, 125, 126, 'CC', 2901, 'SBC', 'ERS', DATE '2026-09-22', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000748, 122, 126, 'CC', 2905, 'SBC', 'ERS', DATE '2026-09-25', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000749, 76, 126, 'CC', 2904, 'SBC', 'ERS', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000750, 2, 126, 'EC', 3003, 'SBC', 'ERS', DATE '2026-09-26', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000751, 139, 126, 'CC', 2810, 'SBC', 'ERS', DATE '2026-09-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000752, 64, 126, 'CC', 2803, 'SBC', 'ERS', DATE '2026-09-30', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000753, 120, 126, 'CC', 2806, 'SBC', 'ERS', DATE '2026-10-01', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000754, 8, 126, 'CC', 2809, 'SBC', 'ERS', DATE '2026-10-11', 'COMPLETED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000755, 133, 127, 'CC', 2807, 'CBE', 'PGT', DATE '2026-09-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000756, 97, 127, 'CC', 2812, 'SBC', 'ERS', DATE '2026-09-22', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000757, 4, 127, 'EC', 3001, 'CBE', 'ERS', DATE '2026-09-23', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000758, 16, 127, 'CC', 2907, 'SBC', 'ERS', DATE '2026-10-01', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000759, 118, 127, 'EC', 3008, 'SBC', 'ERS', DATE '2026-10-02', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000760, 121, 127, 'EC', 3005, 'SBC', 'ERS', DATE '2026-10-04', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000761, 2, 127, 'CC', 2904, 'SBC', 'ERS', DATE '2026-10-09', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000762, 129, 127, 'CC', 2803, 'SBC', 'ERS', DATE '2026-10-10', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000763, 3, 127, 'CC', 2903, 'SBC', 'CBE', DATE '2026-10-10', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000764, 42, 127, 'EC', NULL, 'SBC', 'ERS', DATE '2026-10-10', 'CANCELLED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000765, 147, 127, 'EC', 3007, 'SBC', 'ERS', DATE '2026-10-11', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000766, 101, 127, 'CC', 2801, 'SBC', 'ERS', DATE '2026-10-16', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000767, 17, 127, 'EC', 3006, 'ED', 'CBE', DATE '2026-10-18', 'CONFIRMED');
INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status) VALUES (4200000768, 15, 127, 'CC', 2805, 'SBC', 'PGT', DATE '2026-10-18', 'CONFIRMED');

-- 2.10 PAYMENT : one payment per reservation (INSERT ... SELECT)
INSERT INTO payment (payment_id, pnr, amount, pay_mode, paid_on, pay_status)
SELECT 900000 + ROW_NUMBER() OVER (ORDER BY r.pnr),
       r.pnr,
       r.fare,
       DECODE(MOD(r.pnr, 5), 0, 'UPI', 1, 'CARD', 2, 'UPI', 3, 'NETBANKING', 'WALLET'),
       r.booking_date,
       CASE WHEN r.status = 'CANCELLED' THEN 'PARTIAL_REFUND'
            WHEN r.status = 'WAITLIST' AND s.sched_status = 'COMPLETED' THEN 'REFUNDED'
            ELSE 'SUCCESS' END
FROM   reservation r JOIN train_schedule s ON s.schedule_id = r.schedule_id;

-- 2.11 CANCELLATION : refund policy  >= 2 days before journey : 90%,  1 day : 75%,  same day : 50%
INSERT INTO cancellation (cancel_id, pnr, cancelled_on, refund_amount, reason)
SELECT 700000 + ROW_NUMBER() OVER (ORDER BY r.pnr),
       r.pnr,
       r.booking_date + FLOOR((s.journey_date - r.booking_date) / 2),
       ROUND(r.fare * CASE
               WHEN s.journey_date - (r.booking_date + FLOOR((s.journey_date - r.booking_date) / 2)) >= 2 THEN 0.90
               WHEN s.journey_date - (r.booking_date + FLOOR((s.journey_date - r.booking_date) / 2)) = 1  THEN 0.75
               ELSE 0.50 END, 2),
       DECODE(MOD(r.pnr, 4), 0, 'Change of plans', 1, 'Medical emergency',
                             2, 'Booked alternate travel', 'Official work')
FROM   reservation r JOIN train_schedule s ON s.schedule_id = r.schedule_id
WHERE  r.status = 'CANCELLED';

COMMIT;

-- Row counts of every table
SELECT 'STATION' tbl, COUNT(*) row_count FROM station UNION ALL
SELECT 'ROUTE', COUNT(*) FROM route UNION ALL
SELECT 'ROUTE_STOP', COUNT(*) FROM route_stop UNION ALL
SELECT 'TRAIN', COUNT(*) FROM train UNION ALL
SELECT 'COACH_CLASS', COUNT(*) FROM coach_class UNION ALL
SELECT 'COACH', COUNT(*) FROM coach UNION ALL
SELECT 'SEAT', COUNT(*) FROM seat UNION ALL
SELECT 'TRAIN_SCHEDULE', COUNT(*) FROM train_schedule UNION ALL
SELECT 'PASSENGER', COUNT(*) FROM passenger UNION ALL
SELECT 'RESERVATION', COUNT(*) FROM reservation UNION ALL
SELECT 'PAYMENT', COUNT(*) FROM payment UNION ALL
SELECT 'CANCELLATION', COUNT(*) FROM cancellation;

-- =====================================================================================
--  PART 3 : STRUCTURE MODIFICATION (ALTER)
-- =====================================================================================
-- 3.1 add a concession category to passengers (with domain constraint)
ALTER TABLE passenger ADD (
  concession_type VARCHAR2(10) DEFAULT 'NONE' NOT NULL
  CONSTRAINT ck_pass_concession CHECK (concession_type IN ('NONE','SENIOR','STUDENT','DIVYANG'))
);
-- 3.2 widen a column
ALTER TABLE station MODIFY (station_name VARCHAR2(80));
-- 3.3 rename a column to a clearer name
ALTER TABLE passenger RENAME COLUMN city TO home_city;
-- 3.4 add a table-level constraint after creation
ALTER TABLE train ADD CONSTRAINT uq_train_name UNIQUE (train_name);

-- =====================================================================================
--  PART 4 : MODIFICATION AND DELETION OF RECORDS
-- =====================================================================================
-- 4.1 derive concession category from age
UPDATE passenger SET concession_type = 'SENIOR'  WHERE MONTHS_BETWEEN(SYSDATE, dob) / 12 >= 60;
UPDATE passenger SET concession_type = 'STUDENT' WHERE MONTHS_BETWEEN(SYSDATE, dob) / 12 < 23;
SELECT passenger_id, full_name, TRUNC(MONTHS_BETWEEN(SYSDATE, dob) / 12) age, concession_type
FROM   passenger WHERE concession_type <> 'NONE' ORDER BY passenger_id;

-- 4.2 timetable revision
UPDATE train SET dep_time = '07:40' WHERE train_no = 12639;

-- 4.3 RESERVATION MODIFICATION : passenger changes boarding point MAS -> KPD on an upcoming journey.
--     Setting fare to NULL makes the trigger recalculate the fare for the shorter distance.
VARIABLE v_pnr NUMBER
BEGIN
  SELECT MIN(pnr) INTO :v_pnr FROM reservation
  WHERE  schedule_id = 103 AND status = 'CONFIRMED' AND from_station = 'MAS' AND to_station = 'SBC';
END;
/
SELECT r.pnr, r.from_station, r.to_station, r.fare, p.amount AS paid
FROM   reservation r JOIN payment p ON p.pnr = r.pnr WHERE r.pnr = :v_pnr;

UPDATE reservation SET from_station = 'KPD', fare = NULL WHERE pnr = :v_pnr;
UPDATE payment SET amount = (SELECT fare FROM reservation WHERE pnr = :v_pnr) WHERE pnr = :v_pnr;

SELECT r.pnr, r.from_station, r.to_station, r.fare, p.amount AS paid
FROM   reservation r JOIN payment p ON p.pnr = r.pnr WHERE r.pnr = :v_pnr;

-- 4.4 DELETE : a registered passenger who never booked can be removed
INSERT INTO passenger (passenger_id, full_name, gender, dob, phone, email, home_city)
VALUES (999, 'Test Account', 'M', DATE '1999-05-05', '9000000001', 'test.account@mail.com', 'Chennai');
DELETE FROM passenger WHERE passenger_id = 999;

COMMIT;

-- =====================================================================================
--  PART 5 : ENFORCEMENT OF INTEGRITY - each statement below is EXPECTED TO BE REJECTED
-- =====================================================================================
BEGIN
  INSERT INTO passenger (passenger_id, full_name, gender, dob, phone, email)
  VALUES (998, 'Bad Phone', 'M', DATE '1990-01-01', '12345', 'bad.phone@mail.com');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('5.1 invalid phone       -> ' || SQLERRM);
END;
/
BEGIN   -- seat already sold on journey 101
  INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status)
  SELECT 4299999991, 60, 101, class_code, seat_id, 'MAS', 'SBC', DATE '2026-09-10', 'COMPLETED'
  FROM   reservation WHERE schedule_id = 101 AND seat_id = 101;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('5.2 double seat booking -> ' || SQLERRM);
END;
/
BEGIN   -- seat 2801 is in coach C1 of train 12677, journey 103 is train 12639
  INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, status)
  VALUES (4299999992, 60, 103, 'CC', 2801, 'MAS', 'SBC', 'CONFIRMED');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('5.3 seat of other train -> ' || SQLERRM);
END;
/
BEGIN   -- destination before boarding point
  INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, from_station, to_station, status)
  VALUES (4299999993, 60, 103, 'CC', 'SBC', 'MAS', 'WAITLIST');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('5.4 wrong direction     -> ' || SQLERRM);
END;
/
BEGIN   -- confirmed ticket without a seat
  INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, from_station, to_station, status)
  VALUES (4299999994, 60, 103, 'CC', 'MAS', 'SBC', 'CONFIRMED');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('5.5 confirmed, no seat  -> ' || SQLERRM);
END;
/
BEGIN   -- passenger with bookings cannot be deleted (child rows exist)
  DELETE FROM passenger WHERE passenger_id = 1;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('5.6 delete parent row   -> ' || SQLERRM);
END;
/
BEGIN   -- unknown station code
  INSERT INTO route_stop VALUES (1, 9, 'XYZ', 400);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('5.7 unknown station     -> ' || SQLERRM);
END;
/

-- =====================================================================================
--  PART 6 : SEAT ALLOCATION AND CANCELLATION PROCESSING (stored procedures)
-- =====================================================================================
-- 6.1 BOOK_TICKET : allocates the first free seat of the requested class, else WAITLIST
CREATE OR REPLACE PROCEDURE book_ticket (
  p_passenger IN  NUMBER,
  p_schedule  IN  NUMBER,
  p_class     IN  VARCHAR2,
  p_from      IN  VARCHAR2,
  p_to        IN  VARCHAR2,
  p_mode      IN  VARCHAR2 DEFAULT 'UPI',
  p_pnr       OUT NUMBER,
  p_status    OUT VARCHAR2
) AS
  v_sched_status train_schedule.sched_status%TYPE;
  v_coaches      NUMBER;
  v_seat         seat.seat_id%TYPE;
  v_fare         reservation.fare%TYPE;
BEGIN
  SELECT sched_status INTO v_sched_status FROM train_schedule WHERE schedule_id = p_schedule;
  IF v_sched_status <> 'SCHEDULED' THEN
    RAISE_APPLICATION_ERROR(-20010, 'Booking closed for journey ' || p_schedule);
  END IF;

  SELECT COUNT(*) INTO v_coaches
  FROM   coach c JOIN train_schedule s ON s.train_no = c.train_no
  WHERE  s.schedule_id = p_schedule AND c.class_code = p_class;
  IF v_coaches = 0 THEN
    RAISE_APPLICATION_ERROR(-20011, 'Class ' || p_class || ' is not available on this train');
  END IF;

  SELECT MIN(st.seat_id) INTO v_seat
  FROM   seat st
         JOIN coach c          ON c.coach_id = st.coach_id
         JOIN train_schedule s ON s.train_no = c.train_no
  WHERE  s.schedule_id = p_schedule
  AND    c.class_code  = p_class
  AND    NOT EXISTS (SELECT 1 FROM reservation r
                     WHERE r.schedule_id = p_schedule AND r.seat_id = st.seat_id);

  p_status := CASE WHEN v_seat IS NULL THEN 'WAITLIST' ELSE 'CONFIRMED' END;
  p_pnr    := seq_pnr.NEXTVAL;

  INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id,
                           from_station, to_station, booking_date, status)
  VALUES (p_pnr, p_passenger, p_schedule, p_class, v_seat, p_from, p_to, TRUNC(SYSDATE), p_status)
  RETURNING fare INTO v_fare;

  INSERT INTO payment VALUES (seq_payment.NEXTVAL, p_pnr, v_fare, p_mode, TRUNC(SYSDATE), 'SUCCESS');
END;
/

-- 6.2 CANCEL_TICKET : refund by time-to-departure, release seat, promote first waitlisted ticket
--     Refund : waitlist 100% | >=48 h 90% | >=24 h 75% | >=4 h 50% | <4 h nil
CREATE OR REPLACE PROCEDURE cancel_ticket (p_pnr IN NUMBER, p_reason IN VARCHAR2) AS
  v_status   reservation.status%TYPE;
  v_fare     reservation.fare%TYPE;
  v_seat     reservation.seat_id%TYPE;
  v_sched    reservation.schedule_id%TYPE;
  v_class    reservation.class_code%TYPE;
  v_depart   DATE;
  v_hours    NUMBER;
  v_refund   NUMBER(8,2);
  v_promoted reservation.pnr%TYPE;
BEGIN
  SELECT r.status, r.fare, r.seat_id, r.schedule_id, r.class_code,
         s.journey_date + TO_NUMBER(SUBSTR(t.dep_time, 1, 2)) / 24 + TO_NUMBER(SUBSTR(t.dep_time, 4, 2)) / 1440
  INTO   v_status, v_fare, v_seat, v_sched, v_class, v_depart
  FROM   reservation r
         JOIN train_schedule s ON s.schedule_id = r.schedule_id
         JOIN train t          ON t.train_no    = s.train_no
  WHERE  r.pnr = p_pnr
  FOR UPDATE OF r.status;

  IF v_status NOT IN ('CONFIRMED','WAITLIST') THEN
    RAISE_APPLICATION_ERROR(-20012, 'PNR ' || p_pnr || ' is ' || v_status || ' and cannot be cancelled');
  END IF;
  v_hours := (v_depart - SYSDATE) * 24;
  IF v_hours < 0 THEN
    RAISE_APPLICATION_ERROR(-20013, 'Train has already departed');
  END IF;

  v_refund := ROUND(v_fare * CASE WHEN v_status = 'WAITLIST' THEN 1
                                  WHEN v_hours >= 48 THEN 0.90
                                  WHEN v_hours >= 24 THEN 0.75
                                  WHEN v_hours >= 4  THEN 0.50
                                  ELSE 0 END, 2);

  UPDATE reservation SET status = 'CANCELLED', seat_id = NULL WHERE pnr = p_pnr;
  INSERT INTO cancellation VALUES (seq_cancel.NEXTVAL, p_pnr, TRUNC(SYSDATE), v_refund, p_reason);
  UPDATE payment SET pay_status = CASE WHEN v_refund >= amount THEN 'REFUNDED' ELSE 'PARTIAL_REFUND' END
  WHERE  pnr = p_pnr;
  DBMS_OUTPUT.PUT_LINE('PNR ' || p_pnr || ' cancelled, refund Rs.' || v_refund);

  IF v_seat IS NOT NULL THEN
    UPDATE reservation SET status = 'CONFIRMED', seat_id = v_seat
    WHERE  pnr = (SELECT pnr FROM (SELECT pnr FROM reservation
                                   WHERE  schedule_id = v_sched AND class_code = v_class AND status = 'WAITLIST'
                                   ORDER  BY booking_date, pnr)
                  WHERE ROWNUM = 1)
    RETURNING pnr INTO v_promoted;
    IF v_promoted IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('Waitlisted PNR ' || v_promoted || ' confirmed on released seat ' || v_seat);
    END IF;
  END IF;
END;
/

-- 6.3 DEMO : a new journey of 12677 seven days from today; 9 passengers book the 8-seat EC coach
INSERT INTO train_schedule VALUES (130, 12677, TRUNC(SYSDATE) + 7, 'SCHEDULED');

DECLARE
  v_pnr    NUMBER;
  v_status VARCHAR2(10);
BEGIN
  FOR p IN 11 .. 19 LOOP
    book_ticket(p, 130, 'EC', 'SBC', 'ERS', 'UPI', v_pnr, v_status);
    DBMS_OUTPUT.PUT_LINE('Passenger ' || p || ' -> PNR ' || v_pnr || ' ' || v_status);
  END LOOP;
END;
/
-- 6.4 DEMO : passenger 11 cancels; the waitlisted passenger is promoted automatically
DECLARE
  v_pnr NUMBER;
BEGIN
  SELECT pnr INTO v_pnr FROM reservation WHERE schedule_id = 130 AND passenger_id = 11;
  cancel_ticket(v_pnr, 'Change of plans');
END;
/
SELECT r.pnr, p.full_name, c.coach_label || '-' || st.seat_no seat, r.status, r.fare, pm.pay_status, cn.refund_amount
FROM   reservation r
       JOIN passenger p     ON p.passenger_id = r.passenger_id
       JOIN payment pm      ON pm.pnr = r.pnr
       LEFT JOIN seat st    ON st.seat_id = r.seat_id
       LEFT JOIN coach c    ON c.coach_id = st.coach_id
       LEFT JOIN cancellation cn ON cn.pnr = r.pnr
WHERE  r.schedule_id = 130
ORDER  BY r.pnr;

COMMIT;

-- =====================================================================================
--  PART 7 : VIEWS (derived information reused by the analysis and the risk module)
-- =====================================================================================
-- Metric definitions used everywhere:
--   capacity        = seats in all coaches of a train (per journey)
--   seats occupied  = tickets in status CONFIRMED / COMPLETED
--   occupancy %     = seats occupied / capacity * 100
--   cancellation %  = cancelled tickets / all tickets booked * 100
--   demand %        = (seats occupied + waitlisted) / capacity * 100   (unserved demand included)
--   revenue         = fares of travelled tickets + cancellation charges retained

-- VIEW 1 : RESERVATION PERFORMANCE - one row per journey (train + date)
CREATE OR REPLACE VIEW v_reservation_performance AS
SELECT s.schedule_id,
       t.train_no,
       t.train_name,
       t.route_id,
       s.journey_date,
       s.sched_status,
       cap.capacity,
       COUNT(r.pnr)                                                      AS total_bookings,
       SUM(CASE WHEN r.status IN ('CONFIRMED','COMPLETED') THEN 1 ELSE 0 END) AS seats_occupied,
       SUM(CASE WHEN r.status = 'WAITLIST'  THEN 1 ELSE 0 END)           AS waitlisted,
       SUM(CASE WHEN r.status = 'CANCELLED' THEN 1 ELSE 0 END)           AS cancelled,
       ROUND(100 * SUM(CASE WHEN r.status IN ('CONFIRMED','COMPLETED') THEN 1 ELSE 0 END) / cap.capacity, 2)
                                                                         AS occupancy_pct,
       ROUND(100 * SUM(CASE WHEN r.status = 'CANCELLED' THEN 1 ELSE 0 END) / NULLIF(COUNT(r.pnr), 0), 2)
                                                                         AS cancellation_rate,
       NVL(SUM(CASE WHEN r.status IN ('CONFIRMED','COMPLETED') THEN r.fare
                    WHEN r.status = 'CANCELLED' THEN r.fare - cn.refund_amount END), 0)
                                                                         AS revenue
FROM   train_schedule s
       JOIN train t ON t.train_no = s.train_no
       JOIN (SELECT c.train_no, SUM(cc.seats_per_coach) AS capacity
             FROM   coach c JOIN coach_class cc ON cc.class_code = c.class_code
             GROUP  BY c.train_no) cap ON cap.train_no = t.train_no
       LEFT JOIN reservation  r  ON r.schedule_id = s.schedule_id
       LEFT JOIN cancellation cn ON cn.pnr = r.pnr
GROUP  BY s.schedule_id, t.train_no, t.train_name, t.route_id, s.journey_date, s.sched_status, cap.capacity;

-- VIEW 2 : TRAIN UTILIZATION - one row per train across all its journeys
CREATE OR REPLACE VIEW v_train_utilization AS
SELECT v.train_no,
       v.train_name,
       v.route_id,
       so.city || '-' || sd.city                                         AS route_label,
       COUNT(*)                                                          AS journeys,
       SUM(v.capacity)                                                   AS capacity_offered,
       SUM(v.seats_occupied)                                             AS seats_occupied,
       SUM(v.waitlisted)                                                 AS waitlisted,
       SUM(v.cancelled)                                                  AS cancelled,
       SUM(v.total_bookings)                                             AS total_bookings,
       ROUND(100 * SUM(v.seats_occupied) / SUM(v.capacity), 2)           AS occupancy_pct,
       ROUND(100 * SUM(v.cancelled) / NULLIF(SUM(v.total_bookings), 0), 2) AS cancellation_rate,
       ROUND(100 * (SUM(v.seats_occupied) + SUM(v.waitlisted)) / SUM(v.capacity), 2) AS demand_pct,
       SUM(v.revenue)                                                    AS revenue
FROM   v_reservation_performance v
       JOIN route   ro ON ro.route_id = v.route_id
       JOIN station so ON so.station_code = ro.origin_code
       JOIN station sd ON sd.station_code = ro.dest_code
GROUP  BY v.train_no, v.train_name, v.route_id, so.city, sd.city;

-- VIEW 3 : TICKET DETAILS - de-normalised ticket for enquiry screens
CREATE OR REPLACE VIEW v_ticket_details AS
SELECT r.pnr, p.passenger_id, p.full_name, t.train_no, t.train_name, s.journey_date,
       r.from_station, r.to_station, r.class_code,
       c.coach_label, st.seat_no, st.berth_type,
       (rs2.km_from_origin - rs1.km_from_origin) AS distance_km,
       r.fare, r.status
FROM   reservation r
       JOIN passenger p       ON p.passenger_id = r.passenger_id
       JOIN train_schedule s  ON s.schedule_id = r.schedule_id
       JOIN train t           ON t.train_no = s.train_no
       JOIN route_stop rs1    ON rs1.route_id = t.route_id AND rs1.station_code = r.from_station
       JOIN route_stop rs2    ON rs2.route_id = t.route_id AND rs2.station_code = r.to_station
       LEFT JOIN seat st      ON st.seat_id = r.seat_id
       LEFT JOIN coach c      ON c.coach_id = st.coach_id;

COLUMN train_name   FORMAT A20
COLUMN route_label  FORMAT A22
COLUMN route_name   FORMAT A22
COLUMN station_name FORMAT A27

SELECT * FROM v_reservation_performance ORDER BY train_no, journey_date;
SELECT * FROM v_train_utilization ORDER BY occupancy_pct DESC;

-- =====================================================================================
--  PART 8 : SQL-BASED DATA PROCESSING AND ANALYSIS
-- =====================================================================================

-- Q1 TRAIN-WISE RESERVATION STATISTICS  (conditional aggregation / pivot)
SELECT t.train_no, t.train_name,
       COUNT(*)                                                    AS bookings,
       SUM(CASE WHEN r.status = 'COMPLETED' THEN 1 ELSE 0 END)     AS completed,
       SUM(CASE WHEN r.status = 'CONFIRMED' THEN 1 ELSE 0 END)     AS confirmed,
       SUM(CASE WHEN r.status = 'WAITLIST'  THEN 1 ELSE 0 END)     AS waitlist,
       SUM(CASE WHEN r.status = 'CANCELLED' THEN 1 ELSE 0 END)     AS cancelled,
       ROUND(AVG(r.fare), 2)                                       AS avg_fare,
       MIN(r.booking_date)                                         AS first_booking,
       MAX(r.booking_date)                                         AS last_booking
FROM   reservation r
       JOIN train_schedule s ON s.schedule_id = r.schedule_id
       JOIN train t          ON t.train_no = s.train_no
GROUP  BY t.train_no, t.train_name
ORDER  BY bookings DESC;

-- Q2 STATION-WISE PASSENGER VOLUME  (boarding + alighting, stations with no traffic included)
SELECT st.station_code, st.station_name, st.city,
       NVL(b.boarding, 0)                        AS boarded,
       NVL(a.alighting, 0)                       AS alighted,
       NVL(b.boarding, 0) + NVL(a.alighting, 0)  AS total_footfall
FROM   station st
       LEFT JOIN (SELECT from_station AS code, COUNT(*) AS boarding FROM reservation
                  WHERE status IN ('CONFIRMED','COMPLETED') GROUP BY from_station) b ON b.code = st.station_code
       LEFT JOIN (SELECT to_station AS code, COUNT(*) AS alighting FROM reservation
                  WHERE status IN ('CONFIRMED','COMPLETED') GROUP BY to_station) a   ON a.code = st.station_code
ORDER  BY total_footfall DESC;

-- Q3 ROUTE UTILIZATION
SELECT ro.route_name, ro.distance_km,
       COUNT(*)                                             AS trains,
       SUM(u.journeys)                                      AS journeys,
       SUM(u.capacity_offered)                              AS seats_offered,
       SUM(u.seats_occupied)                                AS seats_sold,
       ROUND(100 * SUM(u.seats_occupied) / SUM(u.capacity_offered), 2) AS route_occupancy_pct,
       SUM(u.revenue)                                       AS revenue
FROM   v_train_utilization u JOIN route ro ON ro.route_id = u.route_id
GROUP  BY ro.route_name, ro.distance_km
ORDER  BY route_occupancy_pct DESC;

-- Q4 COACH OCCUPANCY  (per coach across all journeys of its train)
SELECT t.train_no, t.train_name, c.coach_label, c.class_code,
       cc.seats_per_coach * j.journeys                       AS seat_journeys,
       COUNT(r.pnr)                                          AS occupied,
       ROUND(100 * COUNT(r.pnr) / (cc.seats_per_coach * j.journeys), 1) AS occupancy_pct
FROM   coach c
       JOIN coach_class cc ON cc.class_code = c.class_code
       JOIN train t        ON t.train_no = c.train_no
       JOIN (SELECT train_no, COUNT(*) AS journeys FROM train_schedule GROUP BY train_no) j
                           ON j.train_no = c.train_no
       LEFT JOIN seat st   ON st.coach_id = c.coach_id
       LEFT JOIN reservation r ON r.seat_id = st.seat_id AND r.status IN ('CONFIRMED','COMPLETED')
GROUP  BY t.train_no, t.train_name, c.coach_label, c.class_code, cc.seats_per_coach, j.journeys
ORDER  BY t.train_no, c.coach_label;

-- Q5a CANCELLATION STATISTICS BY TRAIN
SELECT t.train_no, t.train_name,
       COUNT(r.pnr)                                              AS bookings,
       COUNT(cn.cancel_id)                                       AS cancellations,
       ROUND(100 * COUNT(cn.cancel_id) / COUNT(r.pnr), 2)        AS cancel_rate_pct,
       NVL(SUM(cn.refund_amount), 0)                             AS refunded,
       NVL(SUM(CASE WHEN cn.cancel_id IS NOT NULL THEN r.fare - cn.refund_amount END), 0) AS charges_retained,
       ROUND(AVG(s.journey_date - cn.cancelled_on), 1)           AS avg_days_before_journey
FROM   reservation r
       JOIN train_schedule s     ON s.schedule_id = r.schedule_id
       JOIN train t              ON t.train_no = s.train_no
       LEFT JOIN cancellation cn ON cn.pnr = r.pnr
GROUP  BY t.train_no, t.train_name
ORDER  BY cancel_rate_pct DESC;

-- Q5b CANCELLATION REASONS  (share of total using RATIO_TO_REPORT)
SELECT reason, COUNT(*) AS cancellations,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS share_pct,
       SUM(refund_amount) AS refunded
FROM   cancellation
GROUP  BY reason
ORDER  BY cancellations DESC;

-- Q6a PEAK TRAVEL ROUTES  (ranked by passengers carried)
SELECT ro.route_name,
       COUNT(*)                                     AS passengers,
       DENSE_RANK() OVER (ORDER BY COUNT(*) DESC)   AS demand_rank
FROM   reservation r
       JOIN train_schedule s ON s.schedule_id = r.schedule_id
       JOIN train t          ON t.train_no = s.train_no
       JOIN route ro         ON ro.route_id = t.route_id
WHERE  r.status IN ('CONFIRMED','COMPLETED','WAITLIST')
GROUP  BY ro.route_name;

-- Q6b TOP 5 ORIGIN-DESTINATION PAIRS (peak travel segments)
SELECT * FROM (
  SELECT fs.city || ' -> ' || ts.city AS segment, COUNT(*) AS passengers
  FROM   reservation r
         JOIN station fs ON fs.station_code = r.from_station
         JOIN station ts ON ts.station_code = r.to_station
  WHERE  r.status IN ('CONFIRMED','COMPLETED')
  GROUP  BY fs.city, ts.city
  ORDER  BY passengers DESC)
WHERE ROWNUM <= 5;

-- Q6c PEAK TRAVEL DAYS OF THE WEEK
SELECT TO_CHAR(s.journey_date, 'DY') AS travel_day,
       COUNT(*)                      AS passengers,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS share_pct
FROM   reservation r JOIN train_schedule s ON s.schedule_id = r.schedule_id
WHERE  r.status IN ('CONFIRMED','COMPLETED')
GROUP  BY TO_CHAR(s.journey_date, 'DY'), TO_CHAR(s.journey_date, 'D')
ORDER  BY passengers DESC;

-- Q7 HIGHEST AND LOWEST UTILIZED TRAINS
SELECT CASE WHEN rk_high = 1 THEN 'HIGHEST' ELSE 'LOWEST' END AS position,
       train_no, train_name, route_label, occupancy_pct
FROM  (SELECT u.*, RANK() OVER (ORDER BY occupancy_pct DESC) AS rk_high,
                   RANK() OVER (ORDER BY occupancy_pct ASC)  AS rk_low
       FROM   v_train_utilization u)
WHERE  rk_high = 1 OR rk_low = 1;

-- Q8 PASSENGER TRAVEL FREQUENCY  (trips, distance, spend, banding with CASE)
SELECT p.passenger_id, p.full_name, p.home_city,
       COUNT(*)                     AS trips,
       SUM(v.distance_km)           AS km_travelled,
       SUM(v.fare)                  AS total_spent,
       CASE WHEN COUNT(*) >= 6 THEN 'FREQUENT'
            WHEN COUNT(*) >= 3 THEN 'REGULAR'
            ELSE 'OCCASIONAL' END   AS traveller_type
FROM   v_ticket_details v JOIN passenger p ON p.passenger_id = v.passenger_id
WHERE  v.status IN ('CONFIRMED','COMPLETED')
GROUP  BY p.passenger_id, p.full_name, p.home_city
ORDER  BY trips DESC, total_spent DESC;

-- Q9 REVENUE BY TRAIN  (route subtotals and grand total with ROLLUP)
SELECT NVL(ro.route_name, '** ALL ROUTES **')                     AS route_name,
       NVL(t.train_name, DECODE(GROUPING(ro.route_name), 0, '-- route total --', ' ')) AS train_name,
       SUM(pm.amount)                                              AS collected,
       SUM(NVL(cn.refund_amount, 0)
           + CASE WHEN pm.pay_status = 'REFUNDED' AND cn.cancel_id IS NULL THEN pm.amount ELSE 0 END) AS refunded,
       SUM(pm.amount) - SUM(NVL(cn.refund_amount, 0)
           + CASE WHEN pm.pay_status = 'REFUNDED' AND cn.cancel_id IS NULL THEN pm.amount ELSE 0 END) AS net_revenue
FROM   payment pm
       JOIN reservation r        ON r.pnr = pm.pnr
       JOIN train_schedule s     ON s.schedule_id = r.schedule_id
       JOIN train t              ON t.train_no = s.train_no
       JOIN route ro             ON ro.route_id = t.route_id
       LEFT JOIN cancellation cn ON cn.pnr = r.pnr
GROUP  BY ROLLUP (ro.route_name, t.train_name)
ORDER  BY GROUPING(ro.route_name), ro.route_name, GROUPING(t.train_name), net_revenue DESC;

-- Q10 ROUTES REQUIRING ADDITIONAL CAPACITY  (HAVING on aggregated journey data)
SELECT ro.route_name,
       COUNT(*)                                                    AS journeys,
       SUM(CASE WHEN v.occupancy_pct >= 95 THEN 1 ELSE 0 END)      AS sold_out_journeys,
       SUM(v.waitlisted)                                           AS unserved_passengers,
       ROUND(100 * SUM(v.seats_occupied) / SUM(v.capacity), 2)     AS occupancy_pct
FROM   v_reservation_performance v JOIN route ro ON ro.route_id = v.route_id
GROUP  BY ro.route_name
HAVING SUM(v.waitlisted) > 0
   AND 100 * SUM(v.seats_occupied) / SUM(v.capacity) >= 75
ORDER  BY unserved_passengers DESC;

-- =====================================================================================
--  PART 9 : ADVANCED SQL - JOINS, SUBQUERIES, CORRELATED SUBQUERIES
-- =====================================================================================

-- A1 MULTI-TABLE JOIN (11 relations) : complete travel history of one passenger.
--    Station is joined twice (boarding and destination) using table aliases.
SELECT r.pnr, t.train_no, t.train_name, s.journey_date,
       fs.station_name AS boarding, ts.station_name AS destination,
       cc.class_name, c.coach_label || '-' || st.seat_no || ' ' || st.berth_type AS seat,
       r.fare, pm.pay_mode, r.status
FROM   passenger p
       JOIN reservation r     ON r.passenger_id = p.passenger_id
       JOIN train_schedule s  ON s.schedule_id = r.schedule_id
       JOIN train t           ON t.train_no = s.train_no
       JOIN route ro          ON ro.route_id = t.route_id
       JOIN station fs        ON fs.station_code = r.from_station
       JOIN station ts        ON ts.station_code = r.to_station
       JOIN coach_class cc    ON cc.class_code = r.class_code
       JOIN payment pm        ON pm.pnr = r.pnr
       LEFT JOIN seat st      ON st.seat_id = r.seat_id
       LEFT JOIN coach c      ON c.coach_id = st.coach_id
WHERE  p.passenger_id = 1
ORDER  BY s.journey_date;

-- A2 CORRELATED SUBQUERY : trains whose occupancy is above the average occupancy of THEIR route.
--    The inner query is re-evaluated for each outer row using u.route_id.
SELECT u.train_no, u.train_name, u.route_label, u.occupancy_pct,
       (SELECT ROUND(AVG(x.occupancy_pct), 2) FROM v_train_utilization x WHERE x.route_id = u.route_id) AS route_avg_pct
FROM   v_train_utilization u
WHERE  u.occupancy_pct > (SELECT AVG(x.occupancy_pct)
                          FROM   v_train_utilization x
                          WHERE  x.route_id = u.route_id)
ORDER  BY u.route_id, u.occupancy_pct DESC;

-- A3 PASSENGERS WITH REPEATED CANCELLATIONS (2 or more) with cancellation ratio (scalar subquery)
SELECT p.passenger_id, p.full_name,
       COUNT(*)                                                           AS cancellations,
       (SELECT COUNT(*) FROM reservation x WHERE x.passenger_id = p.passenger_id) AS total_bookings,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM reservation x WHERE x.passenger_id = p.passenger_id), 1)
                                                                          AS cancel_ratio_pct,
       LISTAGG(t.train_no, ', ') WITHIN GROUP (ORDER BY s.journey_date)   AS trains_cancelled
FROM   reservation r
       JOIN passenger p      ON p.passenger_id = r.passenger_id
       JOIN train_schedule s ON s.schedule_id = r.schedule_id
       JOIN train t          ON t.train_no = s.train_no
WHERE  r.status = 'CANCELLED'
GROUP  BY p.passenger_id, p.full_name
HAVING COUNT(*) >= 2
ORDER  BY cancellations DESC;

-- A4 NESTED SUBQUERY : routes whose passenger demand is above the average route demand
SELECT ro.route_name, COUNT(*) AS passengers
FROM   reservation r
       JOIN train_schedule s ON s.schedule_id = r.schedule_id
       JOIN train t          ON t.train_no = s.train_no
       JOIN route ro         ON ro.route_id = t.route_id
WHERE  r.status <> 'CANCELLED'
GROUP  BY ro.route_name
HAVING COUNT(*) > (SELECT AVG(route_pax)
                   FROM  (SELECT COUNT(*) AS route_pax
                          FROM   reservation r2
                                 JOIN train_schedule s2 ON s2.schedule_id = r2.schedule_id
                                 JOIN train t2          ON t2.train_no = s2.train_no
                          WHERE  r2.status <> 'CANCELLED'
                          GROUP  BY t2.route_id))
ORDER  BY passengers DESC;

-- A5 STATIONS HANDLING HIGHER-THAN-AVERAGE PASSENGER TRAFFIC (WITH clause + subquery)
WITH footfall AS (
  SELECT station_code, COUNT(*) AS movements
  FROM  (SELECT from_station AS station_code FROM reservation WHERE status IN ('CONFIRMED','COMPLETED')
         UNION ALL
         SELECT to_station FROM reservation WHERE status IN ('CONFIRMED','COMPLETED'))
  GROUP  BY station_code)
SELECT st.station_code, st.station_name, f.movements,
       ROUND((SELECT AVG(movements) FROM footfall), 1) AS network_avg
FROM   footfall f JOIN station st ON st.station_code = f.station_code
WHERE  f.movements > (SELECT AVG(movements) FROM footfall)
ORDER  BY f.movements DESC;

-- A6 TRAINS REQUIRING CAPACITY ENHANCEMENT (correlated NOT EXISTS + EXISTS):
--    every journey ran at >= 90% occupancy AND at least one passenger was left on the waitlist
SELECT u.train_no, u.train_name, u.occupancy_pct, u.waitlisted
FROM   v_train_utilization u
WHERE  NOT EXISTS (SELECT 1 FROM v_reservation_performance v
                   WHERE  v.train_no = u.train_no AND v.occupancy_pct < 90)
AND    EXISTS     (SELECT 1 FROM reservation r JOIN train_schedule s ON s.schedule_id = r.schedule_id
                   WHERE  s.train_no = u.train_no AND r.status = 'WAITLIST');

-- A7 CORRELATED : passengers whose total spend exceeds the average spend of passengers from the same city
SELECT p.passenger_id, p.full_name, p.home_city, SUM(r.fare) AS spent
FROM   passenger p JOIN reservation r ON r.passenger_id = p.passenger_id
WHERE  r.status IN ('CONFIRMED','COMPLETED')
GROUP  BY p.passenger_id, p.full_name, p.home_city
HAVING SUM(r.fare) > (SELECT SUM(r2.fare) / COUNT(DISTINCT r2.passenger_id)
                      FROM   reservation r2 JOIN passenger p2 ON p2.passenger_id = r2.passenger_id
                      WHERE  r2.status IN ('CONFIRMED','COMPLETED')
                      AND    p2.home_city = p.home_city)
ORDER  BY p.home_city, spent DESC;

-- A8 IN / NOT IN : loyal passengers - 3 or more trips on near-full trains (>= 90% occupancy), never cancelled
SELECT p.passenger_id, p.full_name, p.home_city
FROM   passenger p
WHERE  p.passenger_id IN (SELECT r.passenger_id
                          FROM   reservation r JOIN train_schedule s ON s.schedule_id = r.schedule_id
                          WHERE  r.status IN ('CONFIRMED','COMPLETED')
                          AND    s.train_no IN (SELECT train_no FROM v_train_utilization WHERE occupancy_pct >= 90)
                          GROUP  BY r.passenger_id
                          HAVING COUNT(*) >= 3)
AND    p.passenger_id NOT IN (SELECT passenger_id FROM reservation WHERE status = 'CANCELLED')
ORDER  BY p.passenger_id;

-- A9 CORRELATED (on a WITH clause) : coaches whose occupancy % is below the average of their own train's coaches
WITH coach_occ AS (
  SELECT c.train_no, c.coach_id, c.coach_label, c.class_code,
         ROUND(100 * COUNT(r.pnr) / (cc.seats_per_coach * j.journeys), 1) AS occupancy_pct
  FROM   coach c
         JOIN coach_class cc ON cc.class_code = c.class_code
         JOIN (SELECT train_no, COUNT(*) AS journeys FROM train_schedule GROUP BY train_no) j ON j.train_no = c.train_no
         JOIN seat st ON st.coach_id = c.coach_id
         LEFT JOIN reservation r ON r.seat_id = st.seat_id AND r.status IN ('CONFIRMED','COMPLETED')
  GROUP  BY c.train_no, c.coach_id, c.coach_label, c.class_code, cc.seats_per_coach, j.journeys)
SELECT o.train_no, o.coach_label, o.class_code, o.occupancy_pct,
       (SELECT ROUND(AVG(x.occupancy_pct), 1) FROM coach_occ x WHERE x.train_no = o.train_no) AS train_avg_pct
FROM   coach_occ o
WHERE  o.occupancy_pct < (SELECT AVG(x.occupancy_pct) FROM coach_occ x WHERE x.train_no = o.train_no) - 10
ORDER  BY o.train_no, o.coach_label;

-- =====================================================================================
--  PART 10 : BTL-6 CHALLENGE - TRAIN CAPACITY RISK IDENTIFICATION MODULE
-- =====================================================================================
-- Classification rules (thresholds are stored in a table so management can tune them):
--   CAPACITY REQUIRED : occupancy >= 90%  AND  demand >= 100%  AND  cancellation rate <= 10%
--       the train is full, passengers are being turned away (waitlist), and the waitlist is
--       unlikely to clear through cancellations -> attach coaches / run a special train.
--   HIGH DEMAND       : not the above, but occupancy >= 75%  OR  demand >= 90%
--       strong but currently serviceable demand (or high demand offset by many cancellations)
--       -> monitor every week, consider extra quota on peak days.
--   NORMAL            : everything else.
CREATE TABLE risk_threshold (
  param_code   VARCHAR2(20)  CONSTRAINT pk_risk_threshold PRIMARY KEY,
  param_value  NUMBER(6,2)   NOT NULL CONSTRAINT ck_rt_value CHECK (param_value >= 0),
  description  VARCHAR2(100) NOT NULL
);
INSERT INTO risk_threshold VALUES ('CR_MIN_OCCUPANCY',  90, 'Capacity Required: minimum occupancy %');
INSERT INTO risk_threshold VALUES ('CR_MIN_DEMAND',    100, 'Capacity Required: minimum demand % (waitlist exists)');
INSERT INTO risk_threshold VALUES ('CR_MAX_CANCEL',      10, 'Capacity Required: maximum cancellation rate %');
INSERT INTO risk_threshold VALUES ('HD_MIN_OCCUPANCY',  75, 'High Demand: minimum occupancy %');
INSERT INTO risk_threshold VALUES ('HD_MIN_DEMAND',     90, 'High Demand: minimum demand %');

CREATE TABLE capacity_risk_log (
  run_date           DATE         NOT NULL,
  train_no           NUMBER(5)    NOT NULL CONSTRAINT fk_crl_train REFERENCES train(train_no),
  occupancy_pct      NUMBER(6,2),
  cancellation_rate  NUMBER(6,2),
  demand_pct         NUMBER(6,2),
  risk_status        VARCHAR2(20) NOT NULL,
  CONSTRAINT pk_capacity_risk_log PRIMARY KEY (run_date, train_no)
);
COMMIT;

CREATE OR REPLACE FUNCTION fn_capacity_risk (
  p_occupancy NUMBER, p_cancel_rate NUMBER, p_demand NUMBER
) RETURN VARCHAR2 IS
  v_cr_occ NUMBER; v_cr_dem NUMBER; v_cr_can NUMBER; v_hd_occ NUMBER; v_hd_dem NUMBER;
BEGIN
  SELECT MAX(DECODE(param_code, 'CR_MIN_OCCUPANCY', param_value)),
         MAX(DECODE(param_code, 'CR_MIN_DEMAND',    param_value)),
         MAX(DECODE(param_code, 'CR_MAX_CANCEL',    param_value)),
         MAX(DECODE(param_code, 'HD_MIN_OCCUPANCY', param_value)),
         MAX(DECODE(param_code, 'HD_MIN_DEMAND',    param_value))
  INTO   v_cr_occ, v_cr_dem, v_cr_can, v_hd_occ, v_hd_dem
  FROM   risk_threshold;

  IF p_occupancy >= v_cr_occ AND p_demand >= v_cr_dem AND NVL(p_cancel_rate, 0) <= v_cr_can THEN
    RETURN 'CAPACITY REQUIRED';
  ELSIF p_occupancy >= v_hd_occ OR p_demand >= v_hd_dem THEN
    RETURN 'HIGH DEMAND';
  END IF;
  RETURN 'NORMAL';
END;
/

COLUMN "Train"           FORMAT 99999
COLUMN "Route"           FORMAT A22
COLUMN "Risk Status"     FORMAT A18
COLUMN "Recommended Action" FORMAT A45

-- 10.1 DECISION-SUPPORT REPORT
SELECT u.train_no                                                       AS "Train",
       u.route_label                                                    AS "Route",
       u.occupancy_pct                                                  AS "Occupancy %",
       u.cancellation_rate                                              AS "Cancellation Rate",
       u.demand_pct                                                     AS "Average Demand",
       ROUND(AVG(u.occupancy_pct) OVER (PARTITION BY u.route_id), 2)    AS "Route Avg Occ %",
       fn_capacity_risk(u.occupancy_pct, u.cancellation_rate, u.demand_pct) AS "Risk Status",
       CASE fn_capacity_risk(u.occupancy_pct, u.cancellation_rate, u.demand_pct)
            WHEN 'CAPACITY REQUIRED' THEN 'Add ' || CEIL(u.waitlisted / u.journeys) || ' seat(s)/journey: attach extra coach'
            WHEN 'HIGH DEMAND'       THEN 'Monitor weekly; extra quota on peak days'
            ELSE CASE WHEN u.occupancy_pct < 50 THEN 'Under-used: review coach composition'
                      ELSE 'No action' END
       END                                                              AS "Recommended Action"
FROM   v_train_utilization u
ORDER  BY DECODE(fn_capacity_risk(u.occupancy_pct, u.cancellation_rate, u.demand_pct),
                 'CAPACITY REQUIRED', 1, 'HIGH DEMAND', 2, 3),
          u.occupancy_pct DESC;

-- 10.2 PROCEDURE : stores today's classification in CAPACITY_RISK_LOG and prints a summary
CREATE OR REPLACE PROCEDURE prc_capacity_risk_report AS
BEGIN
  DELETE FROM capacity_risk_log WHERE run_date = TRUNC(SYSDATE);
  INSERT INTO capacity_risk_log
  SELECT TRUNC(SYSDATE), train_no, occupancy_pct, cancellation_rate, demand_pct,
         fn_capacity_risk(occupancy_pct, cancellation_rate, demand_pct)
  FROM   v_train_utilization;

  DBMS_OUTPUT.PUT_LINE('TRAIN CAPACITY RISK SUMMARY - ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY'));
  FOR rec IN (SELECT risk_status, COUNT(*) AS trains,
                     LISTAGG(train_no, ', ') WITHIN GROUP (ORDER BY train_no) AS train_list
              FROM   capacity_risk_log WHERE run_date = TRUNC(SYSDATE)
              GROUP  BY risk_status ORDER BY risk_status) LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(rec.risk_status, 20) || rec.trains || ' train(s): ' || rec.train_list);
  END LOOP;
  COMMIT;
END;
/
EXEC prc_capacity_risk_report

-- 10.3 WHAT-IF ANALYSIS : tolerate up to 15% cancellations -> which trains change category?
UPDATE risk_threshold SET param_value = 15 WHERE param_code = 'CR_MAX_CANCEL';
SELECT l.train_no, l.risk_status AS current_status,
       fn_capacity_risk(l.occupancy_pct, l.cancellation_rate, l.demand_pct) AS what_if_status
FROM   capacity_risk_log l
WHERE  l.run_date = TRUNC(SYSDATE)
AND    l.risk_status <> fn_capacity_risk(l.occupancy_pct, l.cancellation_rate, l.demand_pct);
ROLLBACK;
EXIT
