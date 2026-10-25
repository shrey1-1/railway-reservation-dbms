-- =====================================================================================
--  TEST SUITE 06 : ANALYTICAL VIEWS, QUERIES AND DECISION SUPPORT VERIFICATION
-- =====================================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
  v_failures NUMBER := 0;
  v_count    NUMBER;
  v_val      NUMBER;
  v_txt      VARCHAR2(50);

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
  DBMS_OUTPUT.PUT_LINE('--- 1. View v_reservation_performance Verification ---');
  SELECT COUNT(*) INTO v_count FROM v_reservation_performance;
  assert_true('v_reservation_performance returns rows for all active schedules (>= 27)', v_count >= 27);

  -- Check occupancy calculation range [0, 100]
  SELECT COUNT(*) INTO v_count FROM v_reservation_performance
  WHERE occupancy_pct < 0 OR occupancy_pct > 100;
  assert_true('All journey occupancy rates within valid 0-100% bounds', v_count = 0);

  DBMS_OUTPUT.PUT_LINE('--- 2. View v_train_utilization Verification ---');
  SELECT COUNT(*) INTO v_count FROM v_train_utilization;
  assert_true('v_train_utilization returns exactly 9 trains', v_count = 9);

  -- Check top utilized trains (12639 and 12027 should have occupancy >= 96%)
  SELECT occupancy_pct INTO v_val FROM v_train_utilization WHERE train_no = 12639;
  assert_true('Train 12639 occupancy is 96.88%', v_val = 96.88);

  SELECT occupancy_pct INTO v_val FROM v_train_utilization WHERE train_no = 12677;
  assert_true('Train 12677 occupancy is 39.84%', v_val = 39.84);

  DBMS_OUTPUT.PUT_LINE('--- 3. View v_ticket_details Verification ---');
  SELECT COUNT(*) INTO v_count FROM v_ticket_details;
  assert_true('v_ticket_details returns all reservation tickets (>= 768)', v_count >= 768);

  DBMS_OUTPUT.PUT_LINE('--- 4. Decision Support Function fn_capacity_risk Verification ---');
  -- Train 12639: 96.88% occ, 1.96% cancel, 104.17% demand -> CAPACITY REQUIRED
  v_txt := fn_capacity_risk(96.88, 1.96, 104.17);
  assert_true('Rule for 12639 evaluates to CAPACITY REQUIRED', v_txt = 'CAPACITY REQUIRED');

  -- Train 12027: 96.88% occ, 12.50% cancel, 102.08% demand -> HIGH DEMAND (high cancel rate frees seats)
  v_txt := fn_capacity_risk(96.88, 12.50, 102.08);
  assert_true('Rule for 12027 evaluates to HIGH DEMAND', v_txt = 'HIGH DEMAND');

  -- Train 12677: 39.84% occ, 5.56% cancel, 39.84% demand -> NORMAL
  v_txt := fn_capacity_risk(39.84, 5.56, 39.84);
  assert_true('Rule for 12677 evaluates to NORMAL', v_txt = 'NORMAL');

  DBMS_OUTPUT.PUT_LINE('--- 5. Capacity Risk Procedure Execution Verification ---');
  prc_capacity_risk_report;
  SELECT COUNT(*) INTO v_count FROM capacity_risk_log WHERE run_date = TRUNC(SYSDATE);
  assert_true('capacity_risk_log has 9 entries logged for today', v_count = 9);

  SELECT COUNT(*) INTO v_count FROM capacity_risk_log
  WHERE run_date = TRUNC(SYSDATE) AND risk_status = 'CAPACITY REQUIRED';
  assert_true('Exactly 2 trains flagged as CAPACITY REQUIRED (12639 & 12637)', v_count = 2);

  IF v_failures = 0 THEN
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 06 (ANALYTICAL VIEWS & RISK): ALL CHECKS PASSED <<<');
  ELSE
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 06 (ANALYTICAL VIEWS & RISK): ' || v_failures || ' CHECKS FAILED <<<');
  END IF;
END;
/
