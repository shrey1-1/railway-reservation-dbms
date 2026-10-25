-- =====================================================================================
--  TEST SUITE 02 : DATA INTEGRITY AND BUSINESS INVARIANT CHECKS
-- =====================================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
  v_failures NUMBER := 0;
  v_count    NUMBER;

  PROCEDURE assert_zero(p_desc VARCHAR2, p_val NUMBER) IS
  BEGIN
    IF p_val = 0 THEN
      DBMS_OUTPUT.PUT_LINE('[PASS] ' || p_desc || ' (count = 0)');
    ELSE
      DBMS_OUTPUT.PUT_LINE('[FAIL] ' || p_desc || ' (expected 0, found ' || p_val || ')');
      v_failures := v_failures + 1;
    END IF;
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- Checking Core Invariants ---');

  -- Invariant 1: No CONFIRMED/COMPLETED tickets with NULL seat
  SELECT COUNT(*) INTO v_count FROM reservation
  WHERE status IN ('CONFIRMED','COMPLETED') AND seat_id IS NULL;
  assert_zero('CONFIRMED/COMPLETED reservations without seat', v_count);

  -- Invariant 2: No WAITLIST/CANCELLED tickets with assigned seat
  SELECT COUNT(*) INTO v_count FROM reservation
  WHERE status IN ('WAITLIST','CANCELLED') AND seat_id IS NOT NULL;
  assert_zero('WAITLIST/CANCELLED reservations with non-NULL seat', v_count);

  -- Invariant 3: No duplicate seat sold on same journey
  SELECT COUNT(*) INTO v_count FROM (
    SELECT schedule_id, seat_id, COUNT(*) cnt FROM reservation
    WHERE status IN ('CONFIRMED','COMPLETED') AND seat_id IS NOT NULL
    GROUP BY schedule_id, seat_id HAVING COUNT(*) > 1
  );
  assert_zero('Duplicate active seat assignments on same journey', v_count);

  -- Invariant 4: No passenger holds multiple active tickets on same journey
  SELECT COUNT(*) INTO v_count FROM (
    SELECT schedule_id, passenger_id, COUNT(*) cnt FROM reservation
    WHERE status <> 'CANCELLED'
    GROUP BY schedule_id, passenger_id HAVING COUNT(*) > 1
  );
  assert_zero('Duplicate active tickets for same passenger on same journey', v_count);

  -- Invariant 5: Seat belongs to coach of the same train
  SELECT COUNT(*) INTO v_count FROM reservation r
  JOIN seat s ON s.seat_id = r.seat_id
  JOIN coach c ON c.coach_id = s.coach_id
  JOIN train_schedule ts ON ts.schedule_id = r.schedule_id
  WHERE c.train_no <> ts.train_no;
  assert_zero('Reservations assigned seat from wrong train', v_count);

  -- Invariant 6: Seat belongs to coach of booked class
  SELECT COUNT(*) INTO v_count FROM reservation r
  JOIN seat s ON s.seat_id = r.seat_id
  JOIN coach c ON c.coach_id = s.coach_id
  WHERE c.class_code <> r.class_code;
  assert_zero('Reservations assigned seat from wrong class', v_count);

  -- Invariant 7: Station stop sequence validity (from < to)
  SELECT COUNT(*) INTO v_count FROM reservation r
  JOIN train_schedule ts ON ts.schedule_id = r.schedule_id
  JOIN train t ON t.train_no = ts.train_no
  JOIN route_stop rs1 ON rs1.route_id = t.route_id AND rs1.station_code = r.from_station
  JOIN route_stop rs2 ON rs2.route_id = t.route_id AND rs2.station_code = r.to_station
  WHERE rs1.stop_seq >= rs2.stop_seq;
  assert_zero('Reservations with destination preceding boarding', v_count);

  -- Invariant 8: Fare computation consistency
  SELECT COUNT(*) INTO v_count FROM reservation r
  JOIN train_schedule ts ON ts.schedule_id = r.schedule_id
  JOIN train t ON t.train_no = ts.train_no
  JOIN coach_class cc ON cc.class_code = r.class_code
  JOIN route_stop rs1 ON rs1.route_id = t.route_id AND rs1.station_code = r.from_station
  JOIN route_stop rs2 ON rs2.route_id = t.route_id AND rs2.station_code = r.to_station
  WHERE r.fare <> ROUND(GREATEST(rs2.km_from_origin - rs1.km_from_origin, 50) * cc.fare_per_km + cc.reservation_fee, 0);
  assert_zero('Reservations with fare mismatch against formula', v_count);

  -- Invariant 9: Every reservation has a payment record
  SELECT COUNT(*) INTO v_count FROM reservation r
  WHERE NOT EXISTS (SELECT 1 FROM payment p WHERE p.pnr = r.pnr);
  assert_zero('Reservations lacking payment record', v_count);

  -- Invariant 10: Payment amount matches reservation fare
  SELECT COUNT(*) INTO v_count FROM payment p
  JOIN reservation r ON r.pnr = p.pnr
  WHERE p.amount <> r.fare;
  assert_zero('Payments where amount <> reservation fare', v_count);

  -- Invariant 11: Every cancelled reservation has cancellation record
  SELECT COUNT(*) INTO v_count FROM reservation r
  WHERE r.status = 'CANCELLED'
  AND NOT EXISTS (SELECT 1 FROM cancellation c WHERE c.pnr = r.pnr);
  assert_zero('Cancelled reservations lacking cancellation record', v_count);

  -- Invariant 12: No non-cancelled reservation has a cancellation record
  SELECT COUNT(*) INTO v_count FROM cancellation c
  JOIN reservation r ON r.pnr = c.pnr
  WHERE r.status <> 'CANCELLED';
  assert_zero('Active reservations erroneously linked to cancellation record', v_count);

  IF v_failures = 0 THEN
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 02 (DATA INVARIANTS): ALL 12 CHECKS PASSED <<<');
  ELSE
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 02 (DATA INVARIANTS): ' || v_failures || ' CHECKS FAILED <<<');
  END IF;
END;
/
