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
  FOR p IN (SELECT object_name, object_type FROM user_objects
            WHERE object_type IN ('PROCEDURE','FUNCTION')
            AND object_name IN ('BOOK_TICKET','CANCEL_TICKET','PRC_CAPACITY_RISK_REPORT','FN_CAPACITY_RISK')) LOOP
    EXECUTE IMMEDIATE 'DROP ' || p.object_type || ' ' || p.object_name;
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

-- Supporting indexes on foreign keys to eliminate unindexed FK locking and speed up joins
CREATE INDEX ix_res_passenger   ON reservation (passenger_id);
CREATE INDEX ix_res_from_stn    ON reservation (from_station);
CREATE INDEX ix_res_to_stn      ON reservation (to_station);
CREATE INDEX ix_res_seat        ON reservation (seat_id);
CREATE INDEX ix_rs_station      ON route_stop (station_code);
CREATE INDEX ix_train_route     ON train (route_id);
CREATE INDEX ix_coach_class     ON coach (class_code);

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
