-- =====================================================================================
--  TEST SUITE 04 : CANCELLATION, REFUND TIERS AND WAITLIST PROMOTION
-- =====================================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
  v_failures NUMBER := 0;
  v_pnr1     NUMBER;
  v_pnr2     NUMBER;
  v_pnr_wl   NUMBER;
  v_status   VARCHAR2(10);
  v_refund   NUMBER;
  v_pay_stat VARCHAR2(14);
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
  DBMS_OUTPUT.PUT_LINE('--- 1. Setting up Isolated Cancellation Test Fixture (Schedule 198) ---');
  DELETE FROM cancellation WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 198);
  DELETE FROM payment WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 198);
  DELETE FROM reservation WHERE schedule_id = 198;
  DELETE FROM train_schedule WHERE schedule_id = 198;
  -- Schedule departing 3 days from now (>= 48 hours bracket: 90% refund)
  INSERT INTO train_schedule VALUES (198, 12639, TRUNC(SYSDATE) + 3, 'SCHEDULED');

  -- Book all 8 EC seats so seat 301 is booked by passenger 21
  book_ticket(21, 198, 'EC', 'MAS', 'SBC', 'UPI', v_pnr1, v_status);
  FOR p IN 22 .. 28 LOOP
    book_ticket(p, 198, 'EC', 'MAS', 'SBC', 'UPI', v_pnr2, v_status);
  END LOOP;
  -- Book 9th passenger (waitlist)
  book_ticket(29, 198, 'EC', 'MAS', 'SBC', 'UPI', v_pnr_wl, v_status);
  assert_true('Passenger 29 is WAITLIST', v_status = 'WAITLIST');

  DBMS_OUTPUT.PUT_LINE('--- 2. Cancellation of CONFIRMED Ticket (>= 48 Hours) ---');
  cancel_ticket(v_pnr1, 'Test cancellation >=48h');

  -- Verify refund amount (90% of ticket fare)
  SELECT c.refund_amount, ROUND(r.fare * 0.90, 2) INTO v_refund, v_count
  FROM cancellation c JOIN reservation r ON r.pnr = c.pnr WHERE c.pnr = v_pnr1;
  assert_true('Refund amount is 90% of fare', v_refund = v_count);

  -- Verify payment status
  SELECT pay_status INTO v_pay_stat FROM payment WHERE pnr = v_pnr1;
  assert_true('Payment status updated to PARTIAL_REFUND', v_pay_stat = 'PARTIAL_REFUND');

  -- Verify reservation status
  SELECT status, seat_id INTO v_status, v_refund FROM reservation WHERE pnr = v_pnr1;
  assert_true('Reservation status updated to CANCELLED', v_status = 'CANCELLED');
  assert_true('Seat released (seat_id IS NULL)', v_refund IS NULL);

  DBMS_OUTPUT.PUT_LINE('--- 3. Automatic Waitlist Promotion Verification ---');
  -- Passenger 29 should have been promoted to seat 301
  SELECT status, seat_id INTO v_status, v_refund FROM reservation WHERE pnr = v_pnr_wl;
  assert_true('Waitlisted passenger 29 automatically promoted to CONFIRMED', v_status = 'CONFIRMED');
  assert_true('Promoted passenger received released seat 301', v_refund = 301);

  DBMS_OUTPUT.PUT_LINE('--- 4. Cancellation of WAITLIST Ticket (100% Refund) ---');
  -- Book another passenger who becomes waitlisted
  book_ticket(30, 198, 'EC', 'MAS', 'SBC', 'UPI', v_pnr_wl, v_status);
  assert_true('Passenger 30 placed on WAITLIST', v_status = 'WAITLIST');

  cancel_ticket(v_pnr_wl, 'Waitlist passenger voluntary cancellation');
  SELECT c.refund_amount, r.fare INTO v_refund, v_count
  FROM cancellation c JOIN reservation r ON r.pnr = c.pnr WHERE c.pnr = v_pnr_wl;
  assert_true('WAITLIST cancellation received 100% refund', v_refund = v_count);

  SELECT pay_status INTO v_pay_stat FROM payment WHERE pnr = v_pnr_wl;
  assert_true('WAITLIST cancellation payment status is REFUNDED', v_pay_stat = 'REFUNDED');

  DBMS_OUTPUT.PUT_LINE('--- 5. Negative: Duplicate Cancellation Rejection ---');
  BEGIN
    cancel_ticket(v_pnr1, 'Attempting second cancellation');
    assert_true('Double cancellation should be rejected', FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      assert_true('Second cancellation rejected with ORA-20012', SQLCODE = -20012);
  END;

  DBMS_OUTPUT.PUT_LINE('--- 6. Negative: Cancellation on Departed Train ---');
  -- Schedule in past
  UPDATE train_schedule SET journey_date = TRUNC(SYSDATE) - 2 WHERE schedule_id = 198;
  BEGIN
    cancel_ticket(v_pnr2, 'Cancelling departed train ticket');
    assert_true('Cancellation on departed train should be rejected', FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      assert_true('Departed train cancellation rejected with ORA-20013', SQLCODE = -20013);
  END;

  DBMS_OUTPUT.PUT_LINE('--- 7. Negative: Nonexistent PNR Cancellation ---');
  BEGIN
    cancel_ticket(9999999999, 'Invalid PNR');
    assert_true('Nonexistent PNR should be rejected', FALSE);
  EXCEPTION
    WHEN OTHERS THEN
      assert_true('Nonexistent PNR rejected with ORA-20016', SQLCODE = -20016);
  END;

  -- Cleanup test fixture
  ROLLBACK;
  DELETE FROM cancellation WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 198);
  DELETE FROM payment WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 198);
  DELETE FROM reservation WHERE schedule_id = 198;
  DELETE FROM train_schedule WHERE schedule_id = 198;
  COMMIT;

  IF v_failures = 0 THEN
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 04 (CANCELLATION & REFUNDS): ALL CHECKS PASSED <<<');
  ELSE
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 04 (CANCELLATION & REFUNDS): ' || v_failures || ' CHECKS FAILED <<<');
  END IF;
END;
/
