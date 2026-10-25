#!/usr/bin/env python3
"""
Automated Test Runner for Railway Reservation Management System (Oracle PL/SQL)
Course: BCSE302P Database Systems Lab Case Study 6
Executes all SQL test suites via SQL*Plus and verifies data invariants.
"""

import os
import subprocess
import sys
import re

DB_USER = os.environ.get("DB_USER", "railway_test")
DB_PASS = os.environ.get("DB_PASS", "TestPass_2026_Audit")
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "1521")
DB_SERVICE = os.environ.get("DB_SERVICE", "FREEPDB1")

CONNECT_STR = f"{DB_USER}/{DB_PASS}@//{DB_HOST}:{DB_PORT}/{DB_SERVICE}"

def run_sqlplus(command_script: str, cwd: str = None) -> tuple[int, str]:
    sql_input = f"""
SET DEFINE OFF
SET ECHO OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET FEEDBACK OFF
WHENEVER SQLERROR CONTINUE
{command_script}
EXIT;
"""
    cmd = ["sqlplus", "-S", "-L", CONNECT_STR]
    proc = subprocess.run(
        cmd,
        input=sql_input,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="ignore",
        cwd=cwd
    )
    return proc.returncode, proc.stdout + proc.stderr

def main():
    print("=" * 80)
    print("  RAILWAY RESERVATION DBMS — AUTOMATED TEST SUITE EXECUTION")
    print("=" * 80)
    print(f"Target Database: {DB_HOST}:{DB_PORT}/{DB_SERVICE} (User: {DB_USER})")
    
    test_dir = os.path.dirname(os.path.abspath(__file__))
    print(f"Working Directory: {test_dir}")
    print("Executing: @run_all_tests.sql")
    rc, output = run_sqlplus("@run_all_tests.sql", cwd=test_dir)
    
    passes = re.findall(r"\[PASS\]\s+([^\n]+)", output)
    fails = re.findall(r"\[FAIL\]\s+([^\n]+)", output)
    suites = re.findall(r">>>\s+([^\n]+)\s+<<<", output)
    
    print("\n--- TEST SUITE SUMMARY ---")
    for s in suites:
        print(f"  * {s}")
        
    print(f"\nTotal Assertions Passed: {len(passes)}")
    print(f"Total Assertions Failed: {len(fails)}")
    
    if fails:
        print("\nFailures:")
        for f in fails:
            print(f"  [X] {f}")
        sys.exit(1)
        
    print("\n[OK] All test suites passed successfully with zero defects.")
    sys.exit(0)

if __name__ == "__main__":
    main()
