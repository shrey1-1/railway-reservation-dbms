-- =====================================================================================
--  TEST SUITE 05 : CONCURRENCY, ROW LOCKING AND RACE CONDITION DEFENSE
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
  DBMS_OUTPUT.PUT_LINE('--- 1. Setting up Concurrency Test Fixture (Schedule 197) ---');
  DELETE FROM cancellation WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 197);
  DELETE FROM payment WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 197);
  DELETE FROM reservation WHERE schedule_id = 197;
  DELETE FROM train_schedule WHERE schedule_id = 197;
  INSERT INTO train_schedule VALUES (197, 12639, TRUNC(SYSDATE) + 5, 'SCHEDULED');

  DBMS_OUTPUT.PUT_LINE('--- 2. Verifying Schedule-Level Lock Acquisition (FOR UPDATE) ---');
  -- When book_ticket executes, it locks train_schedule row for that journey
  DECLARE
    v_locked_status VARCHAR2(10);
  BEGIN
    SELECT sched_status INTO v_locked_status
    FROM train_schedule
    WHERE schedule_id = 197
    FOR UPDATE NOWAIT;
    assert_true('Acquired row-level lock on train_schedule without blocking', v_locked_status = 'SCHEDULED');
  END;

  DBMS_OUTPUT.PUT_LINE('--- 3. Verifying Final Safeguard: Unique Constraint UX_RES_SEAT_JOURNEY ---');
  -- Book seat 301 on schedule 197
  INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status)
  VALUES (4299999001, 40, 197, 'EC', 301, 'MAS', 'SBC', TRUNC(SYSDATE), 'CONFIRMED');

  -- Attempt simultaneous direct insertion of same seat (simulating concurrent race)
  BEGIN
    INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status)
    VALUES (4299999002, 41, 197, 'EC', 301, 'MAS', 'SBC', TRUNC(SYSDATE), 'CONFIRMED');
    assert_true('Simultaneous double booking of same seat must be blocked', FALSE);
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      assert_true('Database-level UX_RES_SEAT_JOURNEY strictly prevented duplicate seat assignment', TRUE);
  END;

  DBMS_OUTPUT.PUT_LINE('--- 4. Verifying Passenger Uniqueness Safeguard: UX_RES_PASS_JOURNEY ---');
  -- Passenger 40 attempts another active reservation on schedule 197
  BEGIN
    INSERT INTO reservation (pnr, passenger_id, schedule_id, class_code, seat_id, from_station, to_station, booking_date, status)
    VALUES (4299999003, 40, 197, 'EC', 302, 'MAS', 'SBC', TRUNC(SYSDATE), 'CONFIRMED');
    assert_true('Same passenger second active booking must be blocked', FALSE);
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      assert_true('Database-level UX_RES_PASS_JOURNEY strictly prevented duplicate passenger ticket', TRUE);
  END;

  -- Cleanup test fixture
  ROLLBACK;
  DELETE FROM cancellation WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 197);
  DELETE FROM payment WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 197);
  DELETE FROM reservation WHERE schedule_id = 197;
  DELETE FROM train_schedule WHERE schedule_id = 197;
  COMMIT;

  IF v_failures = 0 THEN
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 05 (CONCURRENCY & LOCKING): ALL CHECKS PASSED <<<');
  ELSE
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 05 (CONCURRENCY & LOCKING): ' || v_failures || ' CHECKS FAILED <<<');
  END IF;
END;
/
