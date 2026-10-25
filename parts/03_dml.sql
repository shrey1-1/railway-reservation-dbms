
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
BEGIN   -- confirmed ticket without a seat (booking_date <= journey_date ensures CK_RES_SEAT_STATUS is tested directly)
  INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, from_station, to_station, booking_date, status)
  VALUES (4299999994, 60, 103, 'CC', 'MAS', 'SBC', DATE '2026-10-20', 'CONFIRMED');
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
--     Hardened with: row locking (FOR UPDATE) & DUP_VAL_ON_INDEX bounded retry loop for concurrent safety
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
  v_pax_count    NUMBER;
  v_pax_active   NUMBER;
  v_retries      NUMBER := 0;
BEGIN
  -- Validate passenger existence
  SELECT COUNT(*) INTO v_pax_count FROM passenger WHERE passenger_id = p_passenger;
  IF v_pax_count = 0 THEN
    RAISE_APPLICATION_ERROR(-20015, 'Passenger ' || p_passenger || ' does not exist');
  END IF;

  -- Validate and lock schedule to serialize concurrent allocation per journey
  BEGIN
    SELECT sched_status INTO v_sched_status
    FROM   train_schedule
    WHERE  schedule_id = p_schedule
    FOR UPDATE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20014, 'Journey schedule ' || p_schedule || ' not found');
  END;

  IF v_sched_status <> 'SCHEDULED' THEN
    RAISE_APPLICATION_ERROR(-20010, 'Booking closed for journey ' || p_schedule);
  END IF;

  -- Validate passenger does not already hold an active ticket on this journey (BR8)
  SELECT COUNT(*) INTO v_pax_active
  FROM   reservation
  WHERE  schedule_id = p_schedule
  AND    passenger_id = p_passenger
  AND    status <> 'CANCELLED';

  IF v_pax_active > 0 THEN
    RAISE_APPLICATION_ERROR(-20017, 'Passenger ' || p_passenger || ' already holds an active ticket for journey ' || p_schedule);
  END IF;

  SELECT COUNT(*) INTO v_coaches
  FROM   coach c JOIN train_schedule s ON s.train_no = c.train_no
  WHERE  s.schedule_id = p_schedule AND c.class_code = p_class;
  IF v_coaches = 0 THEN
    RAISE_APPLICATION_ERROR(-20011, 'Class ' || p_class || ' is not available on this train');
  END IF;

  -- Concurrency-safe seat allocation loop: bounded retry if seat race condition is encountered
  LOOP
    v_retries := v_retries + 1;
    IF v_retries > 50 THEN
      RAISE_APPLICATION_ERROR(-20018, 'Seat allocation exceeded max retries due to concurrent demand');
    END IF;

    v_seat := NULL;
    BEGIN
      SELECT seat_id INTO v_seat
      FROM (
        SELECT st.seat_id
        FROM   seat st
               JOIN coach c          ON c.coach_id = st.coach_id
               JOIN train_schedule s ON s.train_no = c.train_no
        WHERE  s.schedule_id = p_schedule
        AND    c.class_code  = p_class
        AND    NOT EXISTS (SELECT 1 FROM reservation r
                           WHERE r.schedule_id = p_schedule AND r.seat_id = st.seat_id)
        ORDER BY st.seat_id
      )
      WHERE ROWNUM = 1;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        v_seat := NULL;
    END;

    p_status := CASE WHEN v_seat IS NULL THEN 'WAITLIST' ELSE 'CONFIRMED' END;
    p_pnr    := seq_pnr.NEXTVAL;

    BEGIN
      INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id,
                               from_station, to_station, booking_date, status)
      VALUES (p_pnr, p_passenger, p_schedule, p_class, v_seat, p_from, p_to, TRUNC(SYSDATE), p_status)
      RETURNING fare INTO v_fare;

      EXIT; -- Insert succeeded
    EXCEPTION
      WHEN DUP_VAL_ON_INDEX THEN
        IF v_seat IS NOT NULL THEN
          -- Candidate seat was taken concurrently: retry for next seat
          NULL;
        ELSE
          RAISE;
        END IF;
    END;
  END LOOP;

  INSERT INTO payment VALUES (seq_payment.NEXTVAL, p_pnr, v_fare, p_mode, TRUNC(SYSDATE), 'SUCCESS');
END;
/

-- 6.2 CANCEL_TICKET : refund by time-to-departure, release seat, promote first waitlisted ticket
--     Refund : waitlist 100% | >=48 h 90% | >=24 h 75% | >=4 h 50% | <4 h nil
--     Hardened with: PNR existence check, serialized waitlist row-level lock (FOR UPDATE)
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
  BEGIN
    SELECT r.status, r.fare, r.seat_id, r.schedule_id, r.class_code,
           s.journey_date + TO_NUMBER(SUBSTR(t.dep_time, 1, 2)) / 24 + TO_NUMBER(SUBSTR(t.dep_time, 4, 2)) / 1440
    INTO   v_status, v_fare, v_seat, v_sched, v_class, v_depart
    FROM   reservation r
           JOIN train_schedule s ON s.schedule_id = r.schedule_id
           JOIN train t          ON t.train_no    = s.train_no
    WHERE  r.pnr = p_pnr
    FOR UPDATE OF r.status;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20016, 'PNR ' || p_pnr || ' does not exist');
  END;

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
  UPDATE payment SET pay_status = CASE WHEN v_refund >= amount THEN 'REFUNDED'
                                       WHEN v_refund > 0 THEN 'PARTIAL_REFUND'
                                       ELSE 'SUCCESS' END
  WHERE  pnr = p_pnr;
  DBMS_OUTPUT.PUT_LINE('PNR ' || p_pnr || ' cancelled, refund Rs.' || v_refund);

  -- Promote earliest waitlisted passenger in FIFO order (loop guards against concurrent promotion)
  IF v_seat IS NOT NULL THEN
    v_promoted := NULL;
    LOOP
      BEGIN
        SELECT pnr INTO v_promoted
        FROM (
          SELECT pnr
          FROM   reservation
          WHERE  schedule_id = v_sched
          AND    class_code  = v_class
          AND    status      = 'WAITLIST'
          ORDER  BY booking_date, pnr
        )
        WHERE ROWNUM = 1;

        UPDATE reservation
        SET    status = 'CONFIRMED', seat_id = v_seat
        WHERE  pnr = v_promoted
        AND    status = 'WAITLIST';

        IF SQL%ROWCOUNT > 0 THEN
          DBMS_OUTPUT.PUT_LINE('Waitlisted PNR ' || v_promoted || ' confirmed on released seat ' || v_seat);
          EXIT;
        END IF;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          v_promoted := NULL;
          EXIT;
      END;
    END LOOP;
  END IF;
END;
/

-- 6.3 DEMO : a new journey of 12677 seven days from today; 9 passengers book the 8-seat EC coach
-- Safe idempotency reset for demo journey 130
DELETE FROM cancellation WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 130);
DELETE FROM payment WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 130);
DELETE FROM reservation WHERE schedule_id = 130;
DELETE FROM train_schedule WHERE schedule_id = 130;
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
