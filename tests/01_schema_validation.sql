-- =====================================================================================
--  TEST SUITE 01 : SCHEMA AND OBJECT VALIDATION
-- =====================================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
  v_failures NUMBER := 0;
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
  DBMS_OUTPUT.PUT_LINE('--- 1. Table Existence Check ---');
  FOR t IN (
    SELECT column_value AS tbl FROM TABLE(sys.odcivarchar2list(
      'STATION','ROUTE','ROUTE_STOP','TRAIN','COACH_CLASS','COACH','SEAT',
      'TRAIN_SCHEDULE','PASSENGER','RESERVATION','PAYMENT','CANCELLATION',
      'RISK_THRESHOLD','CAPACITY_RISK_LOG'
    ))
  ) LOOP
    SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = t.tbl;
    assert_true('Table ' || t.tbl || ' exists', v_count = 1);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('--- 2. Views Existence Check ---');
  FOR v IN (
    SELECT column_value AS vw FROM TABLE(sys.odcivarchar2list(
      'V_RESERVATION_PERFORMANCE','V_TRAIN_UTILIZATION','V_TICKET_DETAILS'
    ))
  ) LOOP
    SELECT COUNT(*) INTO v_count FROM user_views WHERE view_name = v.vw;
    assert_true('View ' || v.vw || ' exists', v_count = 1);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('--- 3. Sequences Existence Check ---');
  FOR s IN (
    SELECT column_value AS seq FROM TABLE(sys.odcivarchar2list(
      'SEQ_PNR','SEQ_PAYMENT','SEQ_CANCEL'
    ))
  ) LOOP
    SELECT COUNT(*) INTO v_count FROM user_sequences WHERE sequence_name = s.seq;
    assert_true('Sequence ' || s.seq || ' exists', v_count = 1);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('--- 4. Stored Objects Validity Check ---');
  FOR p IN (
    SELECT object_name, object_type, status FROM user_objects
    WHERE object_type IN ('PROCEDURE','FUNCTION','TRIGGER','VIEW')
    ORDER BY object_type, object_name
  ) LOOP
    assert_true(p.object_type || ' ' || p.object_name || ' is VALID', p.status = 'VALID');
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('--- 5. Foreign Key Supporting Indexes Check ---');
  FOR idx IN (
    SELECT column_value AS idx_name FROM TABLE(sys.odcivarchar2list(
      'IX_RES_PASSENGER','IX_RES_FROM_STN','IX_RES_TO_STN','IX_RES_SEAT',
      'IX_RS_STATION','IX_TRAIN_ROUTE','IX_COACH_CLASS'
    ))
  ) LOOP
    SELECT COUNT(*) INTO v_count FROM user_indexes WHERE index_name = idx.idx_name;
    assert_true('Index ' || idx.idx_name || ' exists', v_count = 1);
  END LOOP;

  IF v_failures = 0 THEN
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 01 (SCHEMA VALIDATION): ALL CHECKS PASSED <<<');
  ELSE
    DBMS_OUTPUT.PUT_LINE('>>> TEST SUITE 01 (SCHEMA VALIDATION): ' || v_failures || ' CHECKS FAILED <<<');
  END IF;
END;
/
