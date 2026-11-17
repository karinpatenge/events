-- =============================================================================
-- login.sql - session settings for SQLcl, run automatically after each connect
--
-- Author:      Karin Patenge
-- Last update: 2026-11-14
--
-- SQLcl runs a login.sql found only in the current folder with database
-- access restricted ("DB access is restricted for login.sql"), so the
-- ALTER SESSION lines would be skipped. Put this folder into SQLPATH; then
-- the file is trusted and runs completely. Start SQLcl like this
-- (<REPO_PATH> = the folder of your copy of this repository):
--
--   PowerShell:
--     $env:SQLPATH = "<REPO_PATH>\scripts"
--     $env:JAVA_TOOL_OPTIONS = "-Duser.language=en -Duser.country=US"
--     sql /nolog
--   cmd:
--     set SQLPATH=<REPO_PATH>\scripts
--     set JAVA_TOOL_OPTIONS=-Duser.language=en -Duser.country=US
--     sql /nolog
--
-- JAVA_TOOL_OPTIONS switches SQLcl's own messages (e.g. "rows selected") to
-- English; the ALTER SESSION lines below do the same for the database session.
-- When SQLcl starts with /nolog there is no session yet; the ALTER SESSION
-- lines then do nothing and run again after CONNECT.
-- =============================================================================
SET TERMOUT OFF
WHENEVER SQLERROR CONTINUE

-- English Oracle messages, US formats, '.' as decimal and ',' as group separator
ALTER SESSION SET NLS_LANGUAGE = 'AMERICAN' NLS_TERRITORY = 'AMERICA' NLS_NUMERIC_CHARACTERS = '.,';

-- No parallel DML (on by default on the _high and _medium services of
-- Autonomous AI Database): the demo's multi-statement transactions would fail
-- with ORA-12839 or hang. The demo scripts set it themselves as well.
ALTER SESSION DISABLE PARALLEL DML;

-- Readable dates and timestamps (the demo stores timestamps in UTC)
ALTER SESSION SET NLS_DATE_FORMAT      = 'YYYY-MM-DD HH24:MI:SS';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS';
ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI:SS TZR';   -- e.g. SYSTIMESTAMP

SET SQLFORMAT ANSICONSOLE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET TERMOUT ON
