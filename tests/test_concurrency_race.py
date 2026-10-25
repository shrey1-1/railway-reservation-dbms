#!/usr/bin/env python3
"""
Multi-Session Concurrent Booking Race Condition Test
Simulates two concurrent database sessions competing for the final remaining seat.
Verifies that:
 1. No ORA-00001 error or crash occurs.
 2. No duplicate seat assignment is made.
 3. One session gets CONFIRMED and the competing session gracefully receives WAITLIST.
"""

import os
import subprocess
import threading
import sys
import re

DB_USER = os.environ.get("DB_USER", "railway_test")
DB_PASS = os.environ.get("DB_PASS", "TestPass_2026_Audit")
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "1521")
DB_SERVICE = os.environ.get("DB_SERVICE", "FREEPDB1")

CONNECT_STR = f"{DB_USER}/{DB_PASS}@//{DB_HOST}:{DB_PORT}/{DB_SERVICE}"

def execute_sql(sql: str) -> str:
    cmd = ["sqlplus", "-S", "-L", CONNECT_STR]
    proc = subprocess.run(
        cmd,
        input=f"SET DEFINE OFF;\nSET SERVEROUTPUT ON;\nWHENEVER SQLERROR CONTINUE;\n{sql}\nEXIT;\n",
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="ignore"
    )
    return proc.stdout + proc.stderr

def setup_concurrency_fixture():
    setup_sql = """
DELETE FROM cancellation WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 196);
DELETE FROM payment WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 196);
DELETE FROM reservation WHERE schedule_id = 196;
DELETE FROM train_schedule WHERE schedule_id = 196;
-- Journey 196 of train 12639 (Chennai-Bengaluru)
INSERT INTO train_schedule VALUES (196, 12639, TRUNC(SYSDATE) + 12, 'SCHEDULED');

-- Fill 7 out of 8 EC seats so exactly 1 EC seat (seat 308) remains!
DECLARE
  v_pnr NUMBER;
  v_st VARCHAR2(10);
BEGIN
  FOR p IN 51 .. 57 LOOP
    book_ticket(p, 196, 'EC', 'MAS', 'SBC', 'UPI', v_pnr, v_st);
  END LOOP;
END;
/
COMMIT;
"""
    execute_sql(setup_sql)

def worker_book(passenger_id: int, results: dict, worker_id: str):
    sql = f"""
DECLARE
  v_pnr NUMBER;
  v_status VARCHAR2(10);
BEGIN
  book_ticket({passenger_id}, 196, 'EC', 'MAS', 'SBC', 'UPI', v_pnr, v_status);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('RESULT:' || v_pnr || ':' || v_status);
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ERROR:' || SQLERRM);
END;
/
"""
    out = execute_sql(sql)
    results[worker_id] = out

def main():
    print("=" * 80)
    print("  MULTI-SESSION CONCURRENT BOOKING RACE CONDITION VERIFICATION")
    print("=" * 80)
    print("Setting up journey with exactly 1 seat remaining...")
    setup_concurrency_fixture()

    results = {}
    # Passenger 58 and Passenger 59 simultaneously attempt to book the last EC seat
    t1 = threading.Thread(target=worker_book, args=(58, results, "session_1"))
    t2 = threading.Thread(target=worker_book, args=(59, results, "session_2"))

    print("Launching concurrent booking sessions...")
    t1.start()
    t2.start()
    t1.join()
    t2.join()

    print("\nSession 1 output:", results.get("session_1", "").strip())
    print("Session 2 output:", results.get("session_2", "").strip())

    # Check for ORA- errors
    has_error = "ERROR:" in results["session_1"] or "ERROR:" in results["session_2"]
    if has_error:
        print("[FAIL] Unhandled concurrency error encountered!")
        sys.exit(1)

    # Check database state
    verify_sql = """
SELECT r.pnr, r.passenger_id, r.seat_id, r.status
FROM reservation r
WHERE r.schedule_id = 196 AND r.passenger_id IN (58, 59)
ORDER BY r.pnr;
"""
    out_verify = execute_sql(verify_sql)
    print("\nDatabase State for Competing Passengers:\n", out_verify)

    # Verify invariant: 1 CONFIRMED with seat 308, 1 WAITLIST with NULL seat
    check_sql = """
DECLARE
  v_conf NUMBER;
  v_wl NUMBER;
  v_dup NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_conf FROM reservation
  WHERE schedule_id = 196 AND passenger_id IN (58, 59) AND status = 'CONFIRMED' AND seat_id = 308;

  SELECT COUNT(*) INTO v_wl FROM reservation
  WHERE schedule_id = 196 AND passenger_id IN (58, 59) AND status = 'WAITLIST' AND seat_id IS NULL;

  SELECT COUNT(*) INTO v_dup FROM (
    SELECT seat_id, COUNT(*) FROM reservation
    WHERE schedule_id = 196 AND status = 'CONFIRMED'
    GROUP BY seat_id HAVING COUNT(*) > 1
  );

  IF v_conf = 1 AND v_wl = 1 AND v_dup = 0 THEN
    DBMS_OUTPUT.PUT_LINE('CONCURRENCY_VERIFIED');
  ELSE
    DBMS_OUTPUT.PUT_LINE('CONCURRENCY_FAILED: conf=' || v_conf || ' wl=' || v_wl || ' dup=' || v_dup);
  END IF;
END;
/
"""
    out_check = execute_sql(check_sql)
    if "CONCURRENCY_VERIFIED" in out_check:
        print("[PASS] Concurrency integrity verified: 1 passenger confirmed, 1 waitlisted, 0 seat collisions.")
    else:
        print("[FAIL] Concurrency verification check failed:\n", out_check)
        sys.exit(1)

    # Clean up fixture
    execute_sql("""
DELETE FROM cancellation WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 196);
DELETE FROM payment WHERE pnr IN (SELECT pnr FROM reservation WHERE schedule_id = 196);
DELETE FROM reservation WHERE schedule_id = 196;
DELETE FROM train_schedule WHERE schedule_id = 196;
COMMIT;
""")
    sys.exit(0)

if __name__ == "__main__":
    main()
