--------------------------------------------------------------------------------
-- File       : 01_run_all.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Builds the demo schema in one run: calls 02 to 10 one after
--              the other. Not included are 00_create_user.sql (run before,
--              as ADMIN), 98_cleanup.sql and 99_drop_user.sql.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as the demo user, in folder scripts\sql
--              (03, 09a and 09b read the data relative to this folder)
--                cd <project>\scripts\sql
--                sql doag2026@<tns_alias> @01_run_all.sql
-- Log        : logs/sql/01_run_all.log in the project folder with start, end
--              and timings; each called script writes its own log
--              logs/sql/<script>.log
-- Behaviour  : Stops at the first error (WHENEVER SQLERROR in every
--              script). A re-run is possible, all scripts are re-runnable.
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/01_run_all.log

PROMPT
PROMPT ================================================================
PROMPT  DOAG 2026 "Just a sprain?" - build the demo schema
PROMPT ================================================================
SELECT USER AS connected_as,
       TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'Europe/Berlin', 'YYYY-MM-DD HH24:MI:SS') AS start_time
FROM   dual;

SET TIMING ON

PROMPT
PROMPT >>> 02_create_tables.sql
@@02_create_tables.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

PROMPT
PROMPT >>> 03_load_data.sql
@@03_load_data.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

PROMPT
PROMPT >>> 04_create_annotations.sql
@@04_create_annotations.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

PROMPT
PROMPT >>> 05_create_embeddings.sql
@@05_create_embeddings.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

PROMPT
PROMPT >>> 06_create_text_index.sql
@@06_create_text_index.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

PROMPT
PROMPT >>> 07_create_spatial_indexes.sql
@@07_create_spatial_indexes.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

PROMPT
PROMPT >>> 08_create_rdf_network.sql
@@08_create_rdf_network.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

PROMPT
PROMPT >>> 09a_load_knee_kg.sql
@@09a_load_knee_kg.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

PROMPT
PROMPT >>> 09b_load_fma.sql
@@09b_load_fma.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

PROMPT
PROMPT >>> 10_create_property_graph.sql
@@10_create_property_graph.sql
SPOOL ../../logs/sql/01_run_all.log APPEND

SET TIMING OFF

PROMPT
PROMPT ================================================================
SELECT TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'Europe/Berlin', 'YYYY-MM-DD HH24:MI:SS') AS end_time
FROM   dual;
PROMPT  Done. Logs in logs/sql of the project folder, one per script
PROMPT ================================================================

SPOOL OFF
