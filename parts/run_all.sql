-- =====================================================================================
--  MASTER RUNNER SCRIPT : MODULAR EXECUTION
--  Railway Reservation and Passenger Service Management System
--  Executes modular parts in dependency order using SQL*Plus relative prefix (@@):
--    1. 01_ddl.sql     (Clean-up, Tables, Sequences, Indexes, Triggers)
--    2. 02_data.sql    (Static Reference & Operational Sample Data)
--    3. 02b_seat.sql   (Standalone / Idempotent Seat Population Check)
--    4. 03_dml.sql     (Payments, Cancellations, ALTER, DML, Tests, Procedures)
--    5. 04_queries.sql (Views, Queries Q1-Q10, Advanced Queries A1-A9, Risk Module)
-- =====================================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET FEEDBACK ON
WHENEVER SQLERROR CONTINUE

PROMPT ================================================================================
PROMPT [STEP 1/5] Running 01_ddl.sql (Schema Creation and Constraints)...
PROMPT ================================================================================
@@01_ddl.sql

PROMPT ================================================================================
PROMPT [STEP 2/5] Running 02_data.sql (Loading Baseline Sample Data)...
PROMPT ================================================================================
@@02_data.sql

PROMPT ================================================================================
PROMPT [STEP 3/5] Running 02b_seat.sql (Idempotent Seat Validation)...
PROMPT ================================================================================
@@02b_seat.sql

PROMPT ================================================================================
PROMPT [STEP 4/5] Running 03_dml.sql (DML, Tests, Procedures, Demo)...
PROMPT ================================================================================
@@03_dml.sql

PROMPT ================================================================================
PROMPT [STEP 5/5] Running 04_queries.sql (Views, Analytics and Risk Module)...
PROMPT ================================================================================
@@04_queries.sql

PROMPT ================================================================================
PROMPT Master modular execution completed successfully.
PROMPT ================================================================================
