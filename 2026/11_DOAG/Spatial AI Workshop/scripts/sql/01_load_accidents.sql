--------------------------------------------------------------------------------
-- File       : 01_load_accidents.sql
-- Project    : DOAG 2026 - "Spatial AI in Python: Unlocking Machine Learning
--              for Geospatial Intelligence" (workshop)
-- Purpose    : Loads ONE year of accident locations (Unfallatlas, file
--              data/Unfallorte<YEAR>_LinRef.csv) into table ACCIDENTS.
--              One year per run keeps the space needed in the database
--              small:
--                1. SQLcl LOAD of the whole file (all of Germany, about
--                   270,000 rows) into the staging table STG_ACCIDENTS
--                2. Only the rows of the selected region (default:
--                   Nuremberg, about 1,900 rows per year) go into ACCIDENTS,
--                   with explicit conversions and a point geometry
--                3. The staging table is emptied and its space released
--              Run it once for every year you need.
-- Data       : Unfallatlas, accidents with personal injury
--              (c) Statistische Aemter des Bundes und der Laender,
--              Datenlizenz Deutschland - Namensnennung - Version 2.0
--              https://unfallatlas.statistikportal.de/
--              Available as CSV: 2020, 2022, 2023, 2024, 2025
--              (the other years are .txt files with different columns)
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Tool       : SQLcl (LOAD is a SQLcl command)
-- Run        : as the workshop user (00_create_user.sql), in folder
--              scripts/sql, so that the relative paths are correct.
--              Two arguments, both optional; the script asks for each and
--              shows the argument as default (press Enter to accept):
--                1  year to load: 2020, 2022, 2023, 2024 or 2025
--                2  Y = drop the tables of previous loads first (clean
--                   start, e.g. for the first year), N = keep them and add
--                   this year (default)
--                cd <project>\scripts\sql
--                sql %WORKSHOP_USER%@<tns_alias> @01_load_accidents.sql 2024 Y
--                sql %WORKSHOP_USER%@<tns_alias> @01_load_accidents.sql 2025 N
-- Re-runnable: yes, as often as needed, with the same result:
--                - drop Y: ACCIDENTS and STG_ACCIDENTS are dropped (PURGE,
--                  so the space is released at once) and created again
--                - drop N: the rows of the same year are replaced, other
--                  years stay
--              Table LOAD_LOG is never dropped: it keeps the history of all
--              runs. Package LOAD_LOG_PKG is replaced on every run.
--
-- Logging    : two places, both showing the run ID (YYYYMMDD_HH24MISS):
--   1. Log file log/sql/01_load_accidents.log in the project folder,
--      overwritten on every run. It holds everything SQLcl prints,
--      including the LOAD messages and the LOAD settings used. Earlier runs
--      stay in table LOAD_LOG.
--   2. Table LOAD_LOG: one row per step with status (START, OK, INFO,
--      WARNING, ERROR, DONE), row count, seconds since the previous step and
--      message. Rows are written in an autonomous transaction, so an ERROR
--      row stays even when the script stops and rolls back. An ERROR row
--      contains the Oracle error and the line where it happened.
--   Find problems of earlier runs:
--     SELECT * FROM load_log WHERE status IN ('ERROR', 'WARNING')
--     ORDER  BY log_id DESC;
--   All steps of the last run:
--     SELECT * FROM load_log
--     WHERE  run_id = (SELECT MAX(run_id) FROM load_log) ORDER BY log_id;
--   Not in LOAD_LOG, only in the log file: errors of the CREATE TABLE and
--   COMMENT statements and of the SQLcl LOAD command itself (LOAD does not
--   raise an error; the row count check after it does).
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET TIMING OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

-- Path to the data folder, relative to the current directory (scripts/sql)
DEFINE data_dir = ../../data

-- Region kept in ACCIDENTS: start of the official municipality key (AGS,
-- 8 digits = Land, Regierungsbezirk, Kreis, Gemeinde).
--   09564000 = Nuremberg (default)
--   09564    = Nuremberg (all districts of the Kreis, same as above)
--   095      = Middle Franconia,  09 = Bavaria,  empty = all of Germany
-- Mind the database space: Bavaria is about 47,000 rows per year,
-- Germany about 270,000.
DEFINE region_ags = 09564000

--------------------------------------------------------------------------------
-- Year to load and drop option. Both script arguments are optional: if one
-- is missing, &1 or &2 is defined as empty instead of SQLcl asking
-- "Enter value for 1".
-- The run ID (start time) is shown in the log file and stored in LOAD_LOG.
--------------------------------------------------------------------------------
SET TERMOUT OFF
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
SELECT NULL AS "1", NULL AS "2" FROM dual WHERE 1 = 0;
COLUMN year_hint NEW_VALUE year_hint NOPRINT
SELECT CASE WHEN q'[&1]' IS NULL THEN NULL
            ELSE ' [&1, press Enter to accept]' END AS year_hint
FROM   dual;
COLUMN drop_default NEW_VALUE drop_default NOPRINT
SELECT NVL(UPPER(TRIM(q'[&2]')), 'N') AS drop_default FROM dual;
COLUMN run_id NEW_VALUE run_id NOPRINT
SELECT TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'Europe/Berlin', 'YYYYMMDD_HH24MISS') AS run_id
FROM   dual;
SET TERMOUT ON

PROMPT
PROMPT Year of the accident file to load (data/Unfallorte<YEAR>_LinRef.csv):
PROMPT   2020, 2022, 2023, 2024 or 2025
ACCEPT load_year CHAR DEFAULT '&1' PROMPT 'Year&year_hint: '

PROMPT
PROMPT Drop the tables of previous loads first?
PROMPT   Y = drop ACCIDENTS and STG_ACCIDENTS, start clean (all loaded years are lost)
PROMPT   N = keep them and add or replace this year
ACCEPT drop_tables CHAR DEFAULT '&drop_default' PROMPT 'Drop tables (Y/N) [&drop_default, press Enter to accept]: '

SPOOL ../../log/sql/01_load_accidents.log REPLACE

PROMPT
PROMPT === 01 Load accidents &load_year, region AGS &region_ags.*, drop tables &drop_tables, run &run_id ===
SELECT USER                                       AS db_user,
       SYS_CONTEXT('USERENV', 'DB_NAME')          AS db_name,
       SYS_CONTEXT('USERENV', 'SERVICE_NAME')     AS service,
       TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'Europe/Berlin', 'YYYY-MM-DD HH24:MI:SS') AS start_time
FROM   dual;

-- The log objects are created in the current schema: not as ADMIN
BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the workshop user, not as ADMIN.');
  END IF;
END;
/

--==============================================================================
-- 0. Logging: table LOAD_LOG and package LOAD_LOG_PKG
--==============================================================================

CREATE TABLE IF NOT EXISTS load_log (
  log_id      NUMBER GENERATED ALWAYS AS IDENTITY CONSTRAINT load_log_pk PRIMARY KEY,
  run_id      VARCHAR2(30)  NOT NULL,
  logged_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  script      VARCHAR2(60),
  load_year   NUMBER(4),
  region_ags  VARCHAR2(8),
  step        VARCHAR2(60),
  status      VARCHAR2(10),
  row_count   NUMBER,
  elapsed_s   NUMBER,
  message     VARCHAR2(4000)
);

COMMENT ON TABLE  load_log           IS 'One row per step of a load script run';
COMMENT ON COLUMN load_log.run_id    IS 'Start time of the run (YYYYMMDD_HH24MISS), also shown in the log file';
COMMENT ON COLUMN load_log.status    IS 'START, OK, INFO, WARNING, ERROR, DONE';
COMMENT ON COLUMN load_log.elapsed_s IS 'Seconds since the previous row of the same run (DONE: whole run)';

CREATE OR REPLACE PACKAGE load_log_pkg AS
  -- Remembers run, script, year and region for the rest of the session
  PROCEDURE start_run (p_run_id IN VARCHAR2, p_script IN VARCHAR2,
                       p_year   IN NUMBER,   p_region IN VARCHAR2);
  -- Writes one log row (autonomous transaction) and prints it
  PROCEDURE log_step  (p_step    IN VARCHAR2, p_status IN VARCHAR2,
                       p_rows    IN NUMBER   DEFAULT NULL,
                       p_message IN VARCHAR2 DEFAULT NULL);
  -- Call in an exception handler before RAISE: logs the error and its line
  PROCEDURE log_error (p_step IN VARCHAR2, p_stack IN VARCHAR2, p_backtrace IN VARCHAR2);
  -- Last row of the run, with the duration of the whole run
  PROCEDURE end_run;
END load_log_pkg;
/
SHOW ERRORS PACKAGE load_log_pkg

CREATE OR REPLACE PACKAGE BODY load_log_pkg AS
  g_run_id  VARCHAR2(30) := 'unknown';
  g_script  VARCHAR2(60);
  g_year    NUMBER;
  g_region  VARCHAR2(8);
  g_start   TIMESTAMP WITH TIME ZONE;
  g_last    TIMESTAMP WITH TIME ZONE;

  FUNCTION seconds_since (p_ts IN TIMESTAMP WITH TIME ZONE) RETURN NUMBER IS
    l_diff INTERVAL DAY(9) TO SECOND(3);
  BEGIN
    IF p_ts IS NULL THEN
      RETURN NULL;
    END IF;
    l_diff := SYSTIMESTAMP - p_ts;
    RETURN ROUND(EXTRACT(DAY    FROM l_diff) * 86400
               + EXTRACT(HOUR   FROM l_diff) * 3600
               + EXTRACT(MINUTE FROM l_diff) * 60
               + EXTRACT(SECOND FROM l_diff), 1);
  END seconds_since;

  PROCEDURE write_row (p_step IN VARCHAR2, p_status IN VARCHAR2, p_rows IN NUMBER,
                       p_message IN VARCHAR2, p_elapsed IN NUMBER) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO load_log (run_id, script, load_year, region_ags, step, status,
                          row_count, elapsed_s, message)
    VALUES (g_run_id, g_script, g_year, g_region, SUBSTR(p_step, 1, 60),
            SUBSTR(p_status, 1, 10), p_rows, p_elapsed, SUBSTR(p_message, 1, 4000));
    COMMIT;

    DBMS_OUTPUT.PUT_LINE(RPAD(p_status, 8) || RPAD(p_step, 24)
                         || CASE WHEN p_rows IS NOT NULL THEN LPAD(p_rows, 9) ELSE RPAD(' ', 9) END
                         || CASE WHEN p_elapsed IS NOT NULL
                                 THEN LPAD(TO_CHAR(p_elapsed, 'FM99999990.0') || ' s', 11) END
                         || CASE WHEN p_message IS NOT NULL THEN '  ' || p_message END);
  END write_row;

  PROCEDURE start_run (p_run_id IN VARCHAR2, p_script IN VARCHAR2,
                       p_year   IN NUMBER,   p_region IN VARCHAR2) IS
  BEGIN
    g_run_id := p_run_id;
    g_script := p_script;
    g_year   := p_year;
    g_region := p_region;
    g_start  := SYSTIMESTAMP;
    g_last   := g_start;
    write_row('Start', 'START', NULL,
              'user ' || USER || ', db ' || SYS_CONTEXT('USERENV', 'DB_NAME')
              || ', service ' || SYS_CONTEXT('USERENV', 'SERVICE_NAME'), NULL);
  END start_run;

  PROCEDURE log_step (p_step    IN VARCHAR2, p_status IN VARCHAR2,
                      p_rows    IN NUMBER   DEFAULT NULL,
                      p_message IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    write_row(p_step, p_status, p_rows, p_message, seconds_since(g_last));
    g_last := SYSTIMESTAMP;
  END log_step;

  PROCEDURE log_error (p_step IN VARCHAR2, p_stack IN VARCHAR2, p_backtrace IN VARCHAR2) IS
  BEGIN
    log_step(p_step, 'ERROR', NULL,
             RTRIM(p_stack, CHR(10)) || ' | ' || REPLACE(RTRIM(p_backtrace, CHR(10)), CHR(10), ' | '));
  END log_error;

  PROCEDURE end_run IS
  BEGIN
    write_row('Done', 'DONE', NULL, 'whole run', seconds_since(g_start));
  END end_run;
END load_log_pkg;
/
SHOW ERRORS PACKAGE BODY load_log_pkg

-- Start the run and check the parameters
DECLARE
  l_year VARCHAR2(10) := TRIM('&load_year');
BEGIN
  load_log_pkg.start_run('&run_id', '01_load_accidents.sql',
                         CASE WHEN REGEXP_LIKE(l_year, '^[0-9]{4}$') THEN TO_NUMBER(l_year) END,
                         '&region_ags');

  IF l_year IS NULL OR l_year NOT IN ('2020', '2022', '2023', '2024', '2025') THEN
    RAISE_APPLICATION_ERROR(-20002, 'Year "' || l_year || '" is not available as CSV. '
                                    || 'Use 2020, 2022, 2023, 2024 or 2025.');
  END IF;
  IF NOT REGEXP_LIKE(NVL('&region_ags', '0'), '^[0-9]{1,8}$') THEN
    RAISE_APPLICATION_ERROR(-20003, 'region_ags must be up to 8 digits.');
  END IF;
  IF NVL(UPPER(TRIM('&drop_tables')), '?') NOT IN ('Y', 'N') THEN
    RAISE_APPLICATION_ERROR(-20004, 'Drop tables must be Y or N, not "&drop_tables".');
  END IF;

  load_log_pkg.log_step('Check parameters', 'OK', NULL,
                        'year ' || l_year || ', region AGS ' || NVL('&region_ags', '(all)') || '*'
                        || ', drop tables ' || UPPER(TRIM('&drop_tables')));
EXCEPTION
  WHEN OTHERS THEN
    load_log_pkg.log_error('Check parameters', DBMS_UTILITY.FORMAT_ERROR_STACK,
                           DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    RAISE;
END;
/

-- Decimal point in the CSV files, independent of the client setting
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

--==============================================================================
-- 1a. Drop the tables of previous loads (drop tables = Y only)
--     PURGE skips the recycle bin, so the space is released at once.
--     Dropping ACCIDENTS also drops its spatial index; its spatial metadata
--     is deleted explicitly. LOAD_LOG is kept.
--==============================================================================

PROMPT
PROMPT --- 1a. Drop tables of previous loads (drop tables = &drop_tables)
-- DROP TABLE IF EXISTS works on a first run as well. The statements are in
-- PL/SQL (EXECUTE IMMEDIATE) only because they depend on the drop option.
DECLARE
  l_step VARCHAR2(60);
BEGIN
  IF UPPER(TRIM('&drop_tables')) = 'Y' THEN
    l_step := 'Drop ACCIDENTS';
    EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS accidents CASCADE CONSTRAINTS PURGE';
    load_log_pkg.log_step(l_step, 'OK', NULL, 'DROP TABLE IF EXISTS accidents CASCADE CONSTRAINTS PURGE');

    l_step := 'Drop STG_ACCIDENTS';
    EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS stg_accidents CASCADE CONSTRAINTS PURGE';
    load_log_pkg.log_step(l_step, 'OK', NULL, 'DROP TABLE IF EXISTS stg_accidents CASCADE CONSTRAINTS PURGE');

    l_step := 'Drop metadata';
    DELETE FROM user_sdo_geom_metadata WHERE table_name = 'ACCIDENTS';
    load_log_pkg.log_step(l_step, 'OK', SQL%ROWCOUNT, 'spatial metadata of ACCIDENTS deleted; LOAD_LOG kept');
    COMMIT;
  ELSE
    load_log_pkg.log_step('Drop tables', 'INFO', NULL, 'skipped (drop tables = N), tables kept');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    load_log_pkg.log_error(NVL(l_step, 'Drop tables'), DBMS_UTILITY.FORMAT_ERROR_STACK,
                           DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    RAISE;
END;
/

--==============================================================================
-- 1b. Tables (created if they do not exist)
--==============================================================================

PROMPT
PROMPT --- 1b. Tables

-- Staging: one column per column name found in any of the CSV files, all
-- as text. SQLcl LOAD matches the file header to these names (upper case).
-- File columns that are not listed here (OBJECTID, OID_) are ignored,
-- columns missing in a file stay empty.
CREATE TABLE IF NOT EXISTS stg_accidents (
  uidentstlae         VARCHAR2(30),
  uland               VARCHAR2(5),
  uregbez             VARCHAR2(5),
  ukreis              VARCHAR2(5),
  ugemeinde           VARCHAR2(5),
  ujahr               VARCHAR2(5),
  umonat              VARCHAR2(5),
  ustunde             VARCHAR2(5),
  uwochentag          VARCHAR2(5),
  ukategorie          VARCHAR2(5),
  uart                VARCHAR2(5),
  utyp1               VARCHAR2(5),
  ulichtverh          VARCHAR2(5),
  iststrassenzustand  VARCHAR2(5),   -- 2022 and later
  strzustand          VARCHAR2(5),   -- 2020
  istrad              VARCHAR2(5),
  istpkw              VARCHAR2(5),
  istfuss             VARCHAR2(5),
  istkrad             VARCHAR2(5),
  istgkfz             VARCHAR2(5),
  istsonstige         VARCHAR2(5),
  linrefx             VARCHAR2(40),
  linrefy             VARCHAR2(40),
  xgcswgs84           VARCHAR2(40),
  ygcswgs84           VARCHAR2(40),
  plst                VARCHAR2(5)    -- 2023 and later
);

CREATE TABLE IF NOT EXISTS accidents (
  id               NUMBER GENERATED BY DEFAULT AS IDENTITY
                   CONSTRAINT accidents_pk PRIMARY KEY,
  accident_id      VARCHAR2(30),
  acc_year         NUMBER(4)  NOT NULL,
  acc_month        NUMBER(2),
  acc_hour         NUMBER(2),
  weekday          NUMBER(1),
  ags              VARCHAR2(8),
  category         NUMBER(1),
  accident_kind    NUMBER(1),
  accident_type    NUMBER(1),
  light_condition  NUMBER(1),
  road_condition   NUMBER(1),
  is_bicycle       NUMBER(1),
  is_car           NUMBER(1),
  is_pedestrian    NUMBER(1),
  is_motorcycle    NUMBER(1),
  is_goods_vehicle NUMBER(1),
  is_other         NUMBER(1),
  plst             NUMBER(1),
  x_utm32          NUMBER,
  y_utm32          NUMBER,
  lon              NUMBER,
  lat              NUMBER,
  geom             SDO_GEOMETRY
);

COMMENT ON TABLE accidents IS
  'Accidents with personal injury (Unfallatlas). (c) Statistische Aemter des Bundes und der Laender, dl-de/by-2-0';
COMMENT ON COLUMN accidents.accident_id      IS 'UIDENTSTLAE: accident ID of the statistical offices';
COMMENT ON COLUMN accidents.acc_year         IS 'UJAHR: year';
COMMENT ON COLUMN accidents.acc_month        IS 'UMONAT: month 1-12';
COMMENT ON COLUMN accidents.acc_hour         IS 'USTUNDE: hour 0-23';
COMMENT ON COLUMN accidents.weekday          IS 'UWOCHENTAG: 1 = Sunday ... 7 = Saturday';
COMMENT ON COLUMN accidents.ags              IS 'Official municipality key: ULAND, UREGBEZ, UKREIS, UGEMEINDE';
COMMENT ON COLUMN accidents.category         IS 'UKATEGORIE: 1 = killed, 2 = seriously injured, 3 = slightly injured';
COMMENT ON COLUMN accidents.accident_kind    IS 'UART: kind of accident 0-9 (e.g. 5 = collision with a turning or crossing vehicle)';
COMMENT ON COLUMN accidents.accident_type    IS 'UTYP1: type of accident 1-7 (e.g. 2 = turning, 3 = turning into or crossing)';
COMMENT ON COLUMN accidents.light_condition  IS 'ULICHTVERH: 0 = daylight, 1 = twilight, 2 = darkness';
COMMENT ON COLUMN accidents.road_condition   IS 'IstStrassenzustand / STRZUSTAND: 0 = dry, 1 = wet, 2 = slippery (winter)';
COMMENT ON COLUMN accidents.is_bicycle       IS 'IstRad: 1 = bicycle involved';
COMMENT ON COLUMN accidents.is_car           IS 'IstPKW: 1 = car involved';
COMMENT ON COLUMN accidents.is_pedestrian    IS 'IstFuss: 1 = pedestrian involved';
COMMENT ON COLUMN accidents.is_motorcycle    IS 'IstKrad: 1 = motorcycle involved';
COMMENT ON COLUMN accidents.is_goods_vehicle IS 'IstGkfz: 1 = goods vehicle involved';
COMMENT ON COLUMN accidents.is_other         IS 'IstSonstige: 1 = other road user involved';
COMMENT ON COLUMN accidents.plst             IS 'PLST as delivered (2023 and later)';
COMMENT ON COLUMN accidents.x_utm32          IS 'LINREFX: easting, ETRS89 / UTM zone 32N (EPSG:25832), metres';
COMMENT ON COLUMN accidents.y_utm32          IS 'LINREFY: northing, ETRS89 / UTM zone 32N (EPSG:25832), metres';
COMMENT ON COLUMN accidents.lon              IS 'XGCSWGS84: longitude WGS84';
COMMENT ON COLUMN accidents.lat              IS 'YGCSWGS84: latitude WGS84';
COMMENT ON COLUMN accidents.geom             IS 'Point geometry, SRID 4326 (WGS84)';

-- Spatial metadata (needed for the spatial index)
DECLARE
  l_rows PLS_INTEGER;
BEGIN
  INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
  SELECT 'ACCIDENTS', 'GEOM',
         SDO_DIM_ARRAY(SDO_DIM_ELEMENT('Longitude', -180, 180, 0.05),
                       SDO_DIM_ELEMENT('Latitude',   -90,  90, 0.05)),
         4326
  FROM   dual
  WHERE  NOT EXISTS (SELECT 1 FROM user_sdo_geom_metadata
                     WHERE  table_name = 'ACCIDENTS' AND column_name = 'GEOM');
  l_rows := SQL%ROWCOUNT;
  COMMIT;
  load_log_pkg.log_step('Tables', 'OK', NULL,
                        'STG_ACCIDENTS, ACCIDENTS'
                        || CASE WHEN l_rows > 0 THEN ', spatial metadata added' END);
EXCEPTION
  WHEN OTHERS THEN
    load_log_pkg.log_error('Tables', DBMS_UTILITY.FORMAT_ERROR_STACK,
                           DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    RAISE;
END;
/

--==============================================================================
-- 2. CSV file into the staging table (SQLcl LOAD)
--    Semicolon as delimiter: a single ; in the middle of the line. Not
--    doubled: in a script SQLcl takes ;; literally as a two-character
--    delimiter (each line becomes one column, LOAD fails with ORA-00928).
--    Not at the end of the line, where it would end the command.
--    SHOW LOADFORMAT below must show "delimiter ;".
--    No enclosures in the files. TRUNCATE ON empties the staging table
--    before the load.
--==============================================================================

PROMPT
PROMPT --- 2. Load &data_dir/Unfallorte&load_year._LinRef.csv (SQLcl LOAD)
SET LOADFORMAT DEFAULT
SET LOADFORMAT DELIMITED DELIMITER ; ENCLOSURES OFF COLUMN_NAMES ON ENCODING UTF8
SET LOAD DEFAULT
SET LOAD BATCH_ROWS 5000 BATCHES_PER_COMMIT 10 ERRORS 0 TRUNCATE ON UNKNOWN_COLUMNS_FAIL OFF

-- Settings in the log file, to compare with the LOAD messages below
SHOW LOADFORMAT
SHOW LOAD

EXEC load_log_pkg.log_step('LOAD', 'START', NULL, '&data_dir/Unfallorte&load_year._LinRef.csv')

SET TIMING ON
LOAD stg_accidents &data_dir/Unfallorte&load_year._LinRef.csv
SET TIMING OFF

-- LOAD does not abort the script on errors. Therefore check the rows here.
DECLARE
  l_year     PLS_INTEGER := TO_NUMBER('&load_year');
  l_expected PLS_INTEGER;
  l_cnt      PLS_INTEGER;
  l_no_id    PLS_INTEGER;
  l_no_coord PLS_INTEGER;
  l_other_yr PLS_INTEGER;
BEGIN
  l_expected := CASE l_year WHEN 2020 THEN 237994
                            WHEN 2022 THEN 256492
                            WHEN 2023 THEN 269048
                            WHEN 2024 THEN 268519
                            WHEN 2025 THEN 273007 END;

  SELECT COUNT(*),
         COUNT(CASE WHEN uidentstlae IS NULL THEN 1 END),
         COUNT(CASE WHEN linrefx IS NULL OR xgcswgs84 IS NULL THEN 1 END),
         COUNT(CASE WHEN ujahr <> '&load_year' THEN 1 END)
  INTO   l_cnt, l_no_id, l_no_coord, l_other_yr
  FROM   stg_accidents;

  IF l_cnt <> l_expected THEN
    RAISE_APPLICATION_ERROR(-20010, 'STG_ACCIDENTS: ' || l_cnt || ' rows, expected '
                                    || l_expected || '. See the LOAD messages in the log file.');
  END IF;
  load_log_pkg.log_step('LOAD', 'OK', l_cnt, 'rows in STG_ACCIDENTS (expected ' || l_expected || ')');

  IF l_no_coord > 0 THEN
    RAISE_APPLICATION_ERROR(-20011, l_no_coord || ' rows without coordinates. '
                                    || 'Column names in the file header not matched?');
  END IF;
  IF l_other_yr > 0 THEN
    RAISE_APPLICATION_ERROR(-20012, l_other_yr || ' rows in the file are not from &load_year.');
  END IF;

  -- In some files the first header name starts with a byte order mark (BOM).
  -- In the 2025 file that is UIDENTSTLAE. If LOAD did not recognise the
  -- name, the accident ID stays empty; everything else is loaded.
  IF l_no_id > 0 THEN
    load_log_pkg.log_step('Check staging', 'WARNING', l_no_id,
                          'rows without UIDENTSTLAE (accident ID). See the LOAD messages '
                          || 'in the log file for the column it did not match.');
  ELSE
    load_log_pkg.log_step('Check staging', 'OK', NULL, 'coordinates, year and accident ID complete');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    load_log_pkg.log_error('Check staging', DBMS_UTILITY.FORMAT_ERROR_STACK,
                           DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    RAISE;
END;
/

--==============================================================================
-- 3. Staging -> ACCIDENTS, only the selected region
--==============================================================================

PROMPT
PROMPT --- 3. Convert and keep region AGS &region_ags.*
DECLARE
  l_year     PLS_INTEGER := TO_NUMBER('&load_year');
  l_step     VARCHAR2(30);
  l_rows     PLS_INTEGER;
  l_expected PLS_INTEGER;
  l_bike     PLS_INTEGER;
BEGIN
  l_step := 'Delete year';
  DELETE FROM accidents WHERE acc_year = l_year;
  load_log_pkg.log_step(l_step, 'OK', SQL%ROWCOUNT, 'rows of ' || l_year || ' removed before the insert');

  l_step := 'Insert region';
  INSERT INTO accidents (accident_id, acc_year, acc_month, acc_hour, weekday, ags,
                         category, accident_kind, accident_type, light_condition,
                         road_condition, is_bicycle, is_car, is_pedestrian,
                         is_motorcycle, is_goods_vehicle, is_other, plst,
                         x_utm32, y_utm32, lon, lat, geom)
  SELECT uidentstlae,
         TO_NUMBER(ujahr), TO_NUMBER(umonat), TO_NUMBER(ustunde), TO_NUMBER(uwochentag),
         uland || uregbez || ukreis || ugemeinde,
         TO_NUMBER(ukategorie), TO_NUMBER(uart), TO_NUMBER(utyp1), TO_NUMBER(ulichtverh),
         TO_NUMBER(COALESCE(iststrassenzustand, strzustand)),
         TO_NUMBER(istrad), TO_NUMBER(istpkw), TO_NUMBER(istfuss),
         TO_NUMBER(istkrad), TO_NUMBER(istgkfz), TO_NUMBER(istsonstige),
         TO_NUMBER(plst),
         TO_NUMBER(linrefx), TO_NUMBER(linrefy),
         TO_NUMBER(xgcswgs84), TO_NUMBER(ygcswgs84),
         SDO_GEOMETRY(2001, 4326,
                      SDO_POINT_TYPE(TO_NUMBER(xgcswgs84), TO_NUMBER(ygcswgs84), NULL),
                      NULL, NULL)
  FROM   stg_accidents
  WHERE  uland || uregbez || ukreis || ugemeinde LIKE '&region_ags' || '%';
  l_rows := SQL%ROWCOUNT;
  COMMIT;
  load_log_pkg.log_step(l_step, 'OK', l_rows, 'rows into ACCIDENTS');

  -- Expected for Nuremberg (region_ags 09564000 or 09564)
  l_step := 'Check ACCIDENTS';
  SELECT COUNT(CASE WHEN is_bicycle = 1 THEN 1 END)
  INTO   l_bike
  FROM   accidents
  WHERE  acc_year = l_year;

  IF '&region_ags' IN ('09564000', '09564') THEN
    l_expected := CASE l_year WHEN 2020 THEN 1755
                              WHEN 2022 THEN 1926
                              WHEN 2023 THEN 1868
                              WHEN 2024 THEN 1915
                              WHEN 2025 THEN 1746 END;
    IF l_rows <> l_expected THEN
      RAISE_APPLICATION_ERROR(-20013, 'ACCIDENTS ' || l_year || ': ' || l_rows
                                      || ' rows, expected ' || l_expected);
    END IF;
    load_log_pkg.log_step(l_step, 'OK', l_rows,
                          'as expected for Nuremberg, ' || l_bike || ' with bicycle');
  ELSE
    load_log_pkg.log_step(l_step, 'INFO', l_rows,
                          'no expected count for this region, ' || l_bike || ' with bicycle');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    load_log_pkg.log_error(l_step, DBMS_UTILITY.FORMAT_ERROR_STACK,
                           DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    RAISE;
END;
/

--==============================================================================
-- 4. Release the space of the staging table, spatial index, statistics
--==============================================================================

PROMPT
PROMPT --- 4. Empty staging table, spatial index, statistics
DECLARE
  l_step VARCHAR2(30);
  l_mb   NUMBER;
BEGIN
  l_step := 'Truncate staging';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE stg_accidents DROP ALL STORAGE';
  load_log_pkg.log_step(l_step, 'OK', NULL, 'STG_ACCIDENTS emptied, space released');

  -- Created on the first run only, maintained by the inserts afterwards
  l_step := 'Spatial index';
  EXECUTE IMMEDIATE q'[CREATE INDEX IF NOT EXISTS accidents_geom_sidx ON accidents (geom)
                       INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2 PARAMETERS ('layer_gtype=POINT')]';
  load_log_pkg.log_step(l_step, 'OK', NULL, 'ACCIDENTS_GEOM_SIDX');

  l_step := 'Statistics';
  DBMS_STATS.GATHER_TABLE_STATS(ownname => USER, tabname => 'ACCIDENTS', cascade => TRUE);

  SELECT ROUND(NVL(SUM(bytes), 0) / 1024 / 1024, 1) INTO l_mb FROM user_segments;
  load_log_pkg.log_step(l_step, 'OK', NULL, 'schema uses ' || l_mb || ' MB');

  load_log_pkg.end_run;
EXCEPTION
  WHEN OTHERS THEN
    load_log_pkg.log_error(l_step, DBMS_UTILITY.FORMAT_ERROR_STACK,
                           DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    RAISE;
END;
/

--==============================================================================
-- 5. Overview
--==============================================================================

PROMPT
PROMPT --- 5. Rows per year
SELECT acc_year,
       COUNT(*)                                     AS accidents,
       COUNT(CASE WHEN is_bicycle = 1 THEN 1 END)   AS with_bicycle,
       COUNT(CASE WHEN category <= 2 THEN 1 END)    AS killed_or_serious
FROM   accidents
GROUP  BY acc_year
ORDER  BY acc_year;

PROMPT --- Space used (MB)
SELECT segment_name, ROUND(SUM(bytes) / 1024 / 1024, 1) AS mb
FROM   user_segments
GROUP  BY segment_name
ORDER  BY mb DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT --- Log of this run (table LOAD_LOG)
COLUMN step      FORMAT A24
COLUMN status    FORMAT A8
COLUMN message   FORMAT A70 WORD_WRAPPED
SELECT TO_CHAR(logged_at AT TIME ZONE 'Europe/Berlin', 'HH24:MI:SS') AS log_time,
       step, status, row_count, elapsed_s, message
FROM   load_log
WHERE  run_id = '&run_id'
ORDER  BY log_id;

PROMPT
PROMPT Done. Load the next year with: @01_load_accidents.sql <YEAR>

SPOOL OFF
