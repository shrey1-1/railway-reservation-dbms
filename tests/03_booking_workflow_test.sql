-- =====================================================================================
--  TEST SUITE 03 : BOOKING WORKFLOW AND BOUNDARY VALIDATION
-- =====================================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
  v_failures NUMBER := 0;
  v_pnr      NUMBER;
  v_status   VARCHAR2(10);
  v_count    NUMBER;

  PROCEDURE assert_true(p_desc VARCHAR2, p_cond BOOLEAN) IS
  BEGIN
    IF p_cond THEN
      DBMS_OUTPUT.PUT_LINE('[PASS] ' || p_desc);
    ELSE
      DBMS_OUTPUT.PUT_LINE('[FAIL] ' || p_desc);
      v_failures := v_failures + 1;
    END IF;
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- 1. Setting up Isolated Test Schedule (ID 199) ---');
  -- Journey of 12639 (Chennai-Bengaluru) with 2 CC coaches (24 seats) and 1 EC coach (8 seats)
  DELETE FROM cancellation WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 199);
  DELETE FROM payment WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 199);
  DELETE FROM reservation WHERE schedule_id = 199;
  DELETE FROM train_schedule WHERE schedule_id = 199;
  INSERT INTO train_schedule VALUES (199, 12639, TRUNC(SYSDATE) + 10, 'SCHEDULED');

  DBMS_OUTPUT.PUT_LINE('--- 2. Positive Single Booking Test ---');
  book_ticket(1, 199, 'EC', 'MAS', 'SBC', 'UPI', v_pnr, v_status);
  assert_true('Booking returned valid PNR', v_pnr >= 4200001000);
  assert_true('Status is CONFIRMED', v_status = 'CONFIRMED');

  -- Verify reservation record
  SELECT COUNT(*) INTO v_count FROM reservation WHERE pnr = v_pnr AND seat_id = 301 AND status = 'CONFIRMED';
  assert_true('Reservation created with first EC seat (301)', v_count = 1);

  -- Verify payment record
  SELECT COUNT(*) INTO v_count FROM payment p JOIN reservation r ON r.pnr = p.pnr
  WHERE p.pnr = v_pnr AND p.pay_status = 'SUCCESS' AND p.amount = r.fare;
  assert_true('Payment record created for correct fare', v_count = 1);

  DBMS_OUTPUT.PUT_LINE('--- 3. Capacity Overflow into WAITLIST Test ---');
  -- Book remaining 7 seats of EC coach (passengers 2 to 8)
  FOR p IN 2 .. 8 LOOP
    book_ticket(p, 199, 'EC', 'MAS', 'SBC', 'CARD', v_pnr, v_status);
    assert_true('Passenger ' || p || ' confirmed', v_status = 'CONFIRMED');
  END LOOP;

  -- 9th passenger (passenger 9) requests EC: should receive WAITLIST
  book_ticket(9, 199, 'EC', 'MAS', 'SBC', 'UPI', v_pnr, v_status);
  assert_true('9th passenger assigned WAITLIST status', v_status = 'WAITLIST');

  SELECT COUNT(*) INTO v_count FROM reservation WHERE pnr = v_pnr AND seat_id IS NULL AND status = 'WAITLIST';
  assert_true('WAITLIST reservation has NULL seat_id', v_count = 1);

  DBMS_OUTPUT.PUT_LINE('--- 4. Negative: Duplicate Active Booking on Same Journey ---');
  BEGIN
    -- Passenger 1 attempts a second booking on schedule 199
    book_ticket(1, 199, 'CC', 'MAS', 'KPD', 'UPI', v_pnr, v_status);
    assert_true('Duplicate booking should be rejected', FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      assert_true('Duplicate booking rejected (ORA-20017 or ORA-00001)', SQLCODE IN (-20017, -1));
  END;

  DBMS_OUTPUT.PUT_LINE('--- 5. Negative: Nonexistent Passenger ---');
  BEGIN
    book_ticket(99999, 199, 'CC', 'MAS', 'SBC', 'UPI', v_pnr, v_status);
    assert_true('Nonexistent passenger rejected', FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      assert_true('Nonexistent passenger raised ORA-20015', SQLCODE = -20015);
  END;

  DBMS_OUTPUT.PUT_LINE('--- 6. Negative: Nonexistent Schedule ---');
  BEGIN
    book_ticket(10, 9999, 'CC', 'MAS', 'SBC', 'UPI', v_pnr, v_status);
    assert_true('Nonexistent schedule rejected', FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      assert_true('Nonexistent schedule raised ORA-20014', SQLCODE = -20014);
  END;

  DBMS_OUTPUT.PUT_LINE('--- 7. Negative: Closed / Completed Schedule ---');
  UPDATE train_schedule SET sched_status = 'COMPLETED' WHERE schedule_id = 199;
  BEGIN
    book_ticket(10, 199, 'CC', 'MAS', 'SBC', 'UPI', v_pnr, v_status);
    assert_true('Booking on completed schedule rejected', FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      assert_true('Booking on closed schedule raised ORA-20010', SQLCODE = -20010);
  END;

  -- Cleanup test fixture
  ROLLBACK;
  DELETE FROM cancellation WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 199);
  DELETE FROM payment WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 199);
  DELETE FROM reservation WHERE schedule_id = 199;
  DELETE FROM train_schedule WHERE schedule_id = 199;
  COMMIT;

  IF v_failures = 0 THEN
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 03 (BOOKING WORKFLOW): ALL CHECKS PASSED <<<');
  ELSE
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 03 (BOOKING WORKFLOW): ' || v_failures || ' CHECKS FAILED <<<');
  END IF;
END;
/
