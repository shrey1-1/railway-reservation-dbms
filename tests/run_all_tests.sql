-- =====================================================================================
--  MASTER TEST RUNNER : ALL TEST SUITES
--  Railway Reservation and Passenger Service Management System
--  Runs:
--    1. 01_schema_validation.sql
--    2. 02_data_invariants.sql
--    3. 03_booking_workflow_test.sql
--    4. 04_cancellation_refund_test.sql
--    5. 05_concurrency_test.sql
--    6. 06_queries_verification.sql
-- =====================================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET FEEDBACK OFF
WHENEVER SQLERROR CONTINUE

PROMPT ================================================================================
PROMPT RUNNING TEST SUITE 01: SCHEMA AND OBJECT VALIDATION
PROMPT ================================================================================
@@01_schema_validation.sql

PROMPT ================================================================================
PROMPT RUNNING TEST SUITE 02: DATA INTEGRITY AND BUSINESS INVARIANTS
PROMPT ================================================================================
@@02_data_invariants.sql

PROMPT ================================================================================
PROMPT RUNNING TEST SUITE 03: BOOKING WORKFLOW AND BOUNDARY VALIDATION
PROMPT ================================================================================
@@03_booking_workflow_test.sql

PROMPT ================================================================================
PROMPT RUNNING TEST SUITE 04: CANCELLATION, REFUNDS AND WAITLIST PROMOTION
PROMPT ================================================================================
@@04_cancellation_refund_test.sql

PROMPT ================================================================================
PROMPT RUNNING TEST SUITE 05: CONCURRENCY, ROW LOCKING AND RACE CONDITIONS
PROMPT ================================================================================
@@05_concurrency_test.sql

PROMPT ================================================================================
PROMPT RUNNING TEST SUITE 06: ANALYTICAL VIEWS, QUERIES AND DECISION SUPPORT
PROMPT ================================================================================
@@06_queries_verification.sql

PROMPT ================================================================================
PROMPT ALL TEST SUITES COMPLETED.
PROMPT ================================================================================
