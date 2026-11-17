-- =============================================================================
-- test_all.sql - retests tracker steps A5 to C6 in one run and lists PASS/FAIL
--
-- Author:      Karin Patenge
-- Last update: 2026-11-17
--
-- Run as the demo user (GRAPHAI) from the scripts folder in SQLcl:
--
--   SPOOL log/test_all.log
--   @sql/test_all.sql                -- reinstall, checks, simulation  (about 12 min)
--   @sql/test_all.sql clean          -- first 99_teardown.sql (A15), then a fresh install
--   SPOOL OFF
--
-- Argument 1: clean = remove all demo objects first (tests A15). The IoT
--             settings (device host, encrypted device password, publish) are
--             saved before and restored after the fresh install.
--
-- What it does:
--   1. (clean only) 99_teardown.sql                                        A15
--   2. 00c_install_all.sql. It asks the IoT questions: press Enter
--      to keep the current values.                                         A4
--   3. Checks on the fresh install                                         A5-A14
--   4. Act 2 checks in the rehearsal state                                 B1
--   5. Simulation with the job, with waits:
--        one manual step, job runs                                         C1, C2
--        trip PS-04 (2.5 min), then Act 2/3 and agent tool checks          C3, B1-B3
--        bypass BYP-1 (1.75 min)                                           C4
--        repair, bypass closed (1.75 min)                                  C5
--        reset before a rehearsal                                          C6
--   6. Result list and summary. The job is left as it was before the test.
--
-- The checks write into table DH_TEST_RESULTS (kept after the run, in English).
-- The result list is shown in German.
-- If the umlauts look wrong in the console, run chcp 65001
-- in the Windows terminal before starting SQLcl; the spool file is not affected.
-- =============================================================================
SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
WHENEVER SQLERROR CONTINUE

-- No parallel DML: on the _high and _medium services of Autonomous AI Database
-- it is on by default, and the demo's multi-statement transactions then fail
-- with ORA-12839 or hang (parallel servers waiting for the row locks of their
-- own session). It can only be changed outside a transaction (ORA-12841).
COMMIT;
ALTER SESSION DISABLE PARALLEL DML;

-- Optional argument: define 1 as empty if it was not given
COLUMN 1 NEW_VALUE 1 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
COLUMN 1 CLEAR

-- Saved state (defaults first, in case DH_CONFIG does not exist yet)
DEFINE s_host     = ''
DEFINE s_pub      = ''
DEFINE s_sec      = ''
DEFINE s_job      = 'FALSE'
COLUMN s_host    NEW_VALUE s_host    NOPRINT
COLUMN s_pub     NEW_VALUE s_pub     NOPRINT
COLUMN s_sec     NEW_VALUE s_sec     NOPRINT
COLUMN s_job     NEW_VALUE s_job     NOPRINT
SELECT MAX(CASE name WHEN 'IOT_DEVICE_HOST' THEN value END)                      AS s_host,
       MAX(CASE name WHEN 'IOT_PUBLISH' THEN value END)                          AS s_pub,
       MAX(CASE name WHEN 'IOT_DEVICE_PASSWORD' THEN RAWTOHEX(secret_value) END) AS s_sec
FROM   dh_config;
SELECT enabled AS s_job FROM user_scheduler_jobs WHERE job_name = 'DH_TICK_JOB';

COLUMN t_clean  NEW_VALUE t_clean  NOPRINT
COLUMN t_pre    NEW_VALUE t_pre    NOPRINT
SELECT CASE WHEN LOWER('&1') = 'clean' THEN 'Y' ELSE 'N' END                                      AS t_clean,
       CASE WHEN LOWER('&1') = 'clean' THEN '99_teardown.sql' ELSE 'test_skip.sql' END             AS t_pre
FROM   dual;

PROMPT
PROMPT =============================================================================
PROMPT  test_all.sql   clean install: &t_clean   job before the test: &s_job
PROMPT =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Teardown (clean only) and 2. install
-- -----------------------------------------------------------------------------
@@stop_tick_job.sql
PROMPT == 1. Teardown: &t_pre
@@&t_pre
PROMPT == 2. Install. Press Enter at the IoT questions to keep the current values.
@@00c_install_all.sql
SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK OFF

-- Restore the IoT settings saved before (only where the install left them empty)
UPDATE dh_config SET value = '&s_host'
WHERE  name = 'IOT_DEVICE_HOST' AND value IS NULL AND '&s_host' IS NOT NULL;
UPDATE dh_config SET value = '********', secret_value = HEXTORAW('&s_sec')
WHERE  name = 'IOT_DEVICE_PASSWORD' AND secret_value IS NULL AND '&s_sec' IS NOT NULL;
UPDATE dh_config SET value = '&s_pub'
WHERE  name = 'IOT_PUBLISH' AND '&s_pub' IN ('Y', 'N');
COMMIT;
@@stop_tick_job.sql
UNDEFINE s_sec

-- -----------------------------------------------------------------------------
-- Result table and helper
-- -----------------------------------------------------------------------------
-- The table only holds the latest run, so it is simply created again
-- (this also widens the columns of a table from an older version).
DROP TABLE IF EXISTS dh_test_results PURGE;
CREATE TABLE dh_test_results (
  seq         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id          VARCHAR2(5)    NOT NULL,
  check_name  VARCHAR2(200)  NOT NULL,
  expected    VARCHAR2(4000),
  actual      VARCHAR2(4000),
  result      VARCHAR2(4),
  checked_at  TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
);

CREATE OR REPLACE PACKAGE dh_test AS
  PROCEDURE add_result (p_id IN VARCHAR2, p_check IN VARCHAR2, p_expected IN VARCHAR2, p_actual IN VARCHAR2);
  -- cold buildings per district, sorted by district: 'Galgenhof:20, Gleisshammer:20, ...'
  FUNCTION  cold_buildings RETURN VARCHAR2;
  -- German translation of a check name, a heading or a whole value; unknown texts come back unchanged
  FUNCTION  txt (p_key IN VARCHAR2) RETURN VARCHAR2;
  -- Translation of an expected or actual value (whole value or known fragments)
  FUNCTION  val (p_value IN VARCHAR2) RETURN VARCHAR2;
END dh_test;
/
CREATE OR REPLACE PACKAGE BODY dh_test AS
  -- The translations are written with UNISTR, so this file stays plain ASCII
  -- and the umlauts survive any client code page.
  -- TO_CHAR turns the NVARCHAR2 result of UNISTR into VARCHAR2 (no type mix in CASE).

  PROCEDURE add_result (p_id IN VARCHAR2, p_check IN VARCHAR2, p_expected IN VARCHAR2, p_actual IN VARCHAR2) IS
  BEGIN
    INSERT INTO dh_test_results (id, check_name, expected, actual)
    VALUES (p_id, SUBSTRB(p_check, 1, 200), SUBSTRB(p_expected, 1, 4000), SUBSTRB(p_actual, 1, 4000));
    COMMIT;
  END add_result;

  FUNCTION cold_buildings RETURN VARCHAR2 IS
    l_txt VARCHAR2(4000);
  BEGIN
    SELECT SUBSTRB(LISTAGG(district || ':' || n, ', ' ON OVERFLOW TRUNCATE) WITHIN GROUP (ORDER BY district), 1, 4000)
    INTO   l_txt
    FROM  (SELECT district, COUNT(*) n FROM dh_assets
           WHERE  asset_type = 'BUILDING' AND health_status = 'ALARM' GROUP BY district);
    RETURN NVL(l_txt, '-');
  END cold_buildings;

  FUNCTION txt (p_key IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE p_key
      WHEN 'Tables DH_SIM_STATE and DH_JOB_LOG exist' THEN 'Tabellen DH_SIM_STATE und DH_JOB_LOG vorhanden'
      WHEN 'Settings in DH_CONFIG (the 8 expected names)' THEN 'Einstellungen in DH_CONFIG (die 8 erwarteten Namen)'
      WHEN 'Settings with placeholders (< >)' THEN 'Einstellungen mit Platzhaltern (< >)'
      WHEN 'IOT_DEVICE_PASSWORD masked or empty' THEN 'IOT_DEVICE_PASSWORD maskiert oder leer'
      WHEN 'DH_SECRET valid (spec + body)' THEN TO_CHAR(UNISTR('DH_SECRET g\00FCltig (Spezifikation + Body)'))
      WHEN 'Assets PLANT / PUMP_STATION / SUBSTATION / BUILDING' THEN 'Anlagen PLANT / PUMP_STATION / SUBSTATION / BUILDING'
      WHEN 'Pipes' THEN 'Leitungen'
      WHEN 'CITY and district of PS-04' THEN 'CITY und Stadtteil von PS-04'
      WHEN 'BACKFILL readings (7 days, 5-minute steps, 250 values)' THEN 'BACKFILL-Messwerte (7 Tage, 5-Minuten-Schritte, 250 Werte)'
      WHEN 'Property graphs' THEN 'Property Graphs'
      WHEN 'DH_WHATIF (spec + body) and both live views valid' THEN TO_CHAR(UNISTR('DH_WHATIF (Spezifikation + Body) und beide Live-Views g\00FCltig'))
      WHEN 'Open anomalies per asset (rehearsal state)' THEN 'Offene Anomalien je Anlage (Probezustand)'
      WHEN 'Anomaly texts with a decimal comma' THEN 'Anomalietexte mit Dezimalkomma'
      WHEN 'DH_IOT_SYNC valid (spec + body)' THEN TO_CHAR(UNISTR('DH_IOT_SYNC g\00FCltig (Spezifikation + Body)'))
      WHEN 'DH_DEVICE_SIM valid (spec + body)' THEN TO_CHAR(UNISTR('DH_DEVICE_SIM g\00FCltig (Spezifikation + Body)'))
      WHEN 'Simulation status: all pumps running, no bypass' THEN 'Simulationsstatus: alle Pumpen in Betrieb, kein Bypass'
      WHEN 'AGENT_* functions valid' THEN TO_CHAR(UNISTR('AGENT_*-Funktionen g\00FCltig'))
      WHEN 'DH_GRAPH_API valid (spec + body)' THEN TO_CHAR(UNISTR('DH_GRAPH_API g\00FCltig (Spezifikation + Body)'))
      WHEN 'agent_find_root_cause: cold buildings (rehearsal state)' THEN TO_CHAR(UNISTR('agent_find_root_cause: kalte Geb\00E4ude (Probezustand)'))
      WHEN 'DH_JOB_TICK valid' THEN TO_CHAR(UNISTR('DH_JOB_TICK g\00FCltig'))
      WHEN 'Job DH_TICK_JOB and its interval' THEN 'Job DH_TICK_JOB und sein Intervall'
      WHEN 'APEX views and procedures valid' THEN TO_CHAR(UNISTR('APEX-Views und -Prozeduren g\00FCltig'))
      WHEN 'Teardown and fresh install' THEN 'Abbau und Neuinstallation'
      WHEN 'q0 cold buildings (rehearsal state)' THEN TO_CHAR(UNISTR('q0 kalte Geb\00E4ude (Probezustand)'))
      WHEN 'q0b GET_DDL of DH_NETWORK' THEN 'q0b GET_DDL von DH_NETWORK'
      WHEN 'q1 recursive SQL / q2 GRAPH_TABLE / differences' THEN 'q1 rekursives SQL / q2 GRAPH_TABLE / Unterschiede'
      WHEN 'q7 path heat plant -> hospital: steps' THEN 'q7 Pfad Heizwerk -> Krankenhaus: Schritte'
      WHEN 'One step by hand: new SIMULATED readings' THEN 'Ein Schritt von Hand: neue SIMULATED-Messwerte'
      WHEN 'Job runs since the start (SUCCEEDED / other)' THEN TO_CHAR(UNISTR('Jobl\00E4ufe seit dem Start (SUCCEEDED / andere)'))
      WHEN 'Messages in DH_JOB_LOG' THEN 'Meldungen in DH_JOB_LOG'
      WHEN 'PS-04 state' THEN 'Zustand von PS-04'
      WHEN 'Cold buildings after the trip' THEN TO_CHAR(UNISTR('Kalte Geb\00E4ude nach dem Pumpenausfall'))
      WHEN 'Apartments without heat' THEN 'Wohnungen ohne Heizung'
      WHEN 'PS-04 THRESHOLD ALARM (flow or pressure)' THEN 'PS-04 THRESHOLD ALARM (Durchfluss oder Druck)'
      WHEN 'q3 PS-04 explains cold buildings (live)' THEN TO_CHAR(UNISTR('q3 PS-04 erkl\00E4rt kalte Geb\00E4ude (live)'))
      WHEN 'q8 root cause JSON: cold / first incident / PageRank top' THEN 'q8 Ursachen-JSON: kalt / erster Vorfall / PageRank-Spitze'
      WHEN 'PageRank top 4 (equal scores)' THEN 'PageRank Top 4 (gleiche Werte)'
      WHEN 'WCC: buildings cut off without PS-04' THEN TO_CHAR(UNISTR('WCC: abgeschnittene Geb\00E4ude ohne PS-04'))
      WHEN 'WCC: buildings cut off without PS-04, BYP-1 open' THEN TO_CHAR(UNISTR('WCC: abgeschnittene Geb\00E4ude ohne PS-04, BYP-1 offen'))
      WHEN 'Bellman-Ford: HP-A to PS-04 = length of pipe P-0003' THEN TO_CHAR(UNISTR('Bellman-Ford: HP-A bis PS-04 = L\00E4nge von Leitung P-0003'))
      WHEN 'agent_predict_failures after the trip: assets' THEN 'agent_predict_failures nach dem Ausfall: Anlagen'
      WHEN 'Cold buildings with BYP-1 open' THEN TO_CHAR(UNISTR('Kalte Geb\00E4ude mit offenem BYP-1'))
      WHEN 'Cold buildings after the repair' THEN TO_CHAR(UNISTR('Kalte Geb\00E4ude nach der Reparatur'))
      WHEN 'Status after the reset' THEN TO_CHAR(UNISTR('Status nach dem Zur\00FCcksetzen'))
      WHEN 'Open anomalies per asset after the reset' THEN TO_CHAR(UNISTR('Offene Anomalien je Anlage nach dem Zur\00FCcksetzen'))
      WHEN 'Cold buildings after the reset' THEN TO_CHAR(UNISTR('Kalte Geb\00E4ude nach dem Zur\00FCcksetzen'))
      WHEN 'Work orders left from the test' THEN TO_CHAR(UNISTR('Vom Test \00FCbrig gebliebene Arbeitsauftr\00E4ge'))
      WHEN 'Secret round trip: stored masked, read back' THEN TO_CHAR(UNISTR('Geheimnis-Test: maskiert gespeichert, zur\00FCckgelesen'))
      WHEN 'What-if context: set, then clear' THEN TO_CHAR(UNISTR('What-if-Kontext: setzen, dann l\00F6schen'))
      WHEN 'yes' THEN 'ja'
      WHEN 'skipped (run with clean)' THEN TO_CHAR(UNISTR('\00FCbersprungen (mit clean starten)'))
      WHEN 'done, no invalid objects' THEN TO_CHAR(UNISTR('erledigt, keine ung\00FCltigen Objekte'))
      WHEN 'no DDL' THEN 'keine DDL'
      WHEN 'PASS' THEN 'OK'
      WHEN 'FAIL' THEN 'FEHLER'
      WHEN 'no: ' THEN 'nein: '
      WHEN 'error: ' THEN 'Fehler: '
      WHEN 'wrong: ' THEN 'falsch: '
      WHEN 'plain text' THEN 'Klartext'
      WHEN ' invalid objects' THEN TO_CHAR(UNISTR(' ung\00FCltige Objekte'))
      WHEN 'pumps not running' THEN TO_CHAR(UNISTR('Pumpen au\00DFer Betrieb'))
      WHEN 'open bypass' THEN 'Bypass offen'
      WHEN 'wear' THEN TO_CHAR(UNISTR('Verschlei\00DF'))
      WHEN '#h_check' THEN TO_CHAR(UNISTR('Pr\00FCfung'))
      WHEN '#h_expected' THEN 'Erwartet'
      WHEN '#h_actual' THEN TO_CHAR(UNISTR('Tats\00E4chlich'))
      WHEN '#h_result' THEN 'Ergebnis'
      WHEN '#h_checks' THEN TO_CHAR(UNISTR('Pr\00FCfungen'))
      WHEN '#h_passed' THEN 'OK'
      WHEN '#h_failed' THEN 'Fehler'
      WHEN '#h_step' THEN 'Schritt'
      WHEN '#p_results' THEN '== 6. Ergebnisse'
      WHEN '#p_summary' THEN TO_CHAR(UNISTR('== Zusammenfassung je Tracker-Schritt (ein Schritt ist OK, wenn alle seine Pr\00FCfungen OK sind)'))
      WHEN '#p_total' THEN '== Gesamt'
      WHEN '#p_note1' THEN TO_CHAR(UNISTR('Jeder Tracker-Schritt von A5 bis C6 sollte oben stehen. Fehlt einer, hat eine Pr\00FCfung einen Fehler'))
      WHEN '#p_note2' THEN TO_CHAR(UNISTR('ausgel\00F6st: in der Spool-Datei nach "ORA-" oder "Error" suchen.'))
      ELSE p_key
    END;
  END txt;

  FUNCTION val (p_value IN VARCHAR2) RETURN VARCHAR2 IS
    TYPE t_list IS TABLE OF VARCHAR2(100);
    l_frag t_list := t_list('no: ', 'error: ', 'wrong: ', 'plain text', ' invalid objects', 'pumps not running', 'open bypass', 'wear');
    l_out  VARCHAR2(4000) := p_value;
  BEGIN
    IF p_value IS NULL THEN
      RETURN NULL;
    ELSIF txt(p_value) <> p_value THEN
      RETURN txt(p_value);
    END IF;
    FOR i IN 1 .. l_frag.COUNT LOOP
      l_out := REPLACE(l_out, l_frag(i), txt(l_frag(i)));
    END LOOP;
    RETURN l_out;
  END val;
END dh_test;
/

-- Expected cold buildings per district (Nuremberg): PS-04 in Galgenhof feeds PS-05 in
-- Gleisshammer; the stuck sensor SS-09.3 is in Laufamholz
DEFINE e_base   = 'Laufamholz:5'
DEFINE e_trip   = 'Galgenhof:20, Gleisshammer:20, Laufamholz:5'
DEFINE e_bypass = 'Galgenhof:20, Laufamholz:5'
DEFINE e_ps04   = 'Galgenhof'

-- -----------------------------------------------------------------------------
-- 3. Checks on the fresh install (A5-A15)
-- -----------------------------------------------------------------------------
PROMPT == 3. Checks on the install (A5-A15)
EXEC dh_analytics.run

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A5', 'Tables DH_SIM_STATE and DH_JOB_LOG exist', '2', TO_CHAR(COUNT(*))
FROM   user_tables WHERE table_name IN ('DH_SIM_STATE', 'DH_JOB_LOG');
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A5', 'Settings in DH_CONFIG (the 8 expected names)',
       'CITY, INGEST_MODE, IOT_DEVICE_ENDPOINT, IOT_DEVICE_HOST, IOT_DEVICE_PASSWORD, IOT_PUBLISH, SIM_ENABLED, SIM_LAST_TICK',
       SUBSTRB(LISTAGG(name, ', ' ON OVERFLOW TRUNCATE) WITHIN GROUP (ORDER BY name), 1, 4000)
FROM   dh_config;
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A5', 'Settings with placeholders (< >)', '0', TO_CHAR(COUNT(*)) FROM dh_config WHERE value LIKE '%<%';
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A5', 'IOT_DEVICE_PASSWORD masked or empty', 'yes',
       CASE WHEN MAX(value) IS NULL OR MAX(value) = '********' THEN 'yes' ELSE 'no: plain text' END
FROM   dh_config WHERE name = 'IOT_DEVICE_PASSWORD';
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A5', 'DH_SECRET valid (spec + body)', '2', TO_CHAR(COUNT(*))
FROM   user_objects WHERE object_name = 'DH_SECRET' AND status = 'VALID';
DECLARE
  l_value  dh_config.value%TYPE;
  l_plain  VARCHAR2(100);
BEGIN
  dh_secret.set_secret('TEST_SECRET', 'Test-123 secret');
  SELECT value INTO l_value FROM dh_config WHERE name = 'TEST_SECRET';
  l_plain := dh_secret.get_secret('TEST_SECRET');
  DELETE FROM dh_config WHERE name = 'TEST_SECRET';
  COMMIT;
  dh_test.add_result('A5', 'Secret round trip: stored masked, read back', '******** / ok',
                     l_value || ' / ' || CASE WHEN l_plain = 'Test-123 secret' THEN 'ok' ELSE 'wrong: ' || l_plain END);
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  dh_test.add_result('A5', 'Secret round trip: stored masked, read back', '******** / ok', 'error: ' || SQLERRM);
END;
/

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A6', 'Assets PLANT / PUMP_STATION / SUBSTATION / BUILDING', '2 / 10 / 40 / 200',
       COUNT(CASE WHEN asset_type = 'PLANT' THEN 1 END) || ' / ' || COUNT(CASE WHEN asset_type = 'PUMP_STATION' THEN 1 END)
       || ' / ' || COUNT(CASE WHEN asset_type = 'SUBSTATION' THEN 1 END) || ' / ' || COUNT(CASE WHEN asset_type = 'BUILDING' THEN 1 END)
FROM   dh_assets;
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A6', 'Pipes', '253', TO_CHAR(COUNT(*)) FROM dh_pipes;
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A6', 'CITY and district of PS-04', 'NUE / &e_ps04',
       (SELECT value FROM dh_config WHERE name = 'CITY') || ' / ' || (SELECT district FROM dh_assets WHERE asset_id = 'PS-04')
FROM   dual;

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A7', 'BACKFILL readings (7 days, 5-minute steps, 250 values)', '504000', TO_CHAR(COUNT(*))
FROM   dh_telemetry WHERE source = 'BACKFILL';

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A8', 'Property graphs', 'DH_DEPENDENCY, DH_LIVE_NETWORK, DH_NETWORK',
       SUBSTRB(LISTAGG(graph_name, ', ' ON OVERFLOW TRUNCATE) WITHIN GROUP (ORDER BY graph_name), 1, 4000)
FROM   user_property_graphs WHERE graph_name LIKE 'DH%';
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A8', 'DH_WHATIF (spec + body) and both live views valid', '4', TO_CHAR(COUNT(*))
FROM   user_objects WHERE object_name IN ('DH_WHATIF', 'DH_ASSETS_LIVE_V', 'DH_PIPES_LIVE_V') AND status = 'VALID';
DECLARE
  l_set   VARCHAR2(200);
  l_clear VARCHAR2(200);
BEGIN
  dh_whatif.set_scenario('PS-04', 'BYP-1');
  l_set := SYS_CONTEXT('DH_CTX', 'OOS') || ' | ' || SYS_CONTEXT('DH_CTX', 'OPEN_VALVES');
  dh_whatif.clear;
  l_clear := NVL(SYS_CONTEXT('DH_CTX', 'OOS'), '-');
  dh_test.add_result('A8', 'What-if context: set, then clear', 'PS-04 | BYP-1 / -', l_set || ' / ' || l_clear);
EXCEPTION WHEN OTHERS THEN
  dh_test.add_result('A8', 'What-if context: set, then clear', 'PS-04 | BYP-1 / -', 'error: ' || SQLERRM);
END;
/

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A9', 'Open anomalies per asset (rehearsal state)', 'PS-04:4, PS-08:1, SS-09.3:2',
       SUBSTRB(LISTAGG(asset_id || ':' || n, ', ' ON OVERFLOW TRUNCATE) WITHIN GROUP (ORDER BY asset_id), 1, 4000)
FROM  (SELECT asset_id, COUNT(*) n FROM dh_anomalies WHERE status <> 'CLOSED' GROUP BY asset_id);
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A9', 'Anomaly texts with a decimal comma', '0', TO_CHAR(COUNT(*))
FROM   dh_anomalies WHERE status <> 'CLOSED' AND REGEXP_LIKE(details, '[0-9],[0-9]');

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A10', 'DH_IOT_SYNC valid (spec + body)', '2', TO_CHAR(COUNT(*))
FROM   user_objects WHERE object_name = 'DH_IOT_SYNC' AND status = 'VALID';

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A11', 'DH_DEVICE_SIM valid (spec + body)', '2', TO_CHAR(COUNT(*))
FROM   user_objects WHERE object_name = 'DH_DEVICE_SIM' AND status = 'VALID';
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A11', 'Simulation status: all pumps running, no bypass', 'yes',
       CASE WHEN dh_device_sim.status LIKE 'pumps not running: - | open bypass: - |%' THEN 'yes' ELSE dh_device_sim.status END
FROM   dual;

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A12', 'AGENT_* functions valid', '10', TO_CHAR(COUNT(*))
FROM   user_objects WHERE object_name LIKE 'AGENT\_%' ESCAPE '\' AND object_type = 'FUNCTION' AND status = 'VALID';
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A12', 'DH_GRAPH_API valid (spec + body)', '2', TO_CHAR(COUNT(*))
FROM   user_objects WHERE object_name = 'DH_GRAPH_API' AND status = 'VALID';
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A12', 'agent_find_root_cause: cold buildings (rehearsal state)', '5',
       JSON_VALUE(agent_find_root_cause(), '$.cold_buildings')
FROM   dual;

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A13', 'DH_JOB_TICK valid', '1', TO_CHAR(COUNT(*))
FROM   user_objects WHERE object_name = 'DH_JOB_TICK' AND status = 'VALID';
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A13', 'Job DH_TICK_JOB and its interval', 'FREQ=SECONDLY;INTERVAL=30', MAX(repeat_interval)
FROM   user_scheduler_jobs WHERE job_name = 'DH_TICK_JOB';

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A14', 'APEX views and procedures valid', '4', TO_CHAR(COUNT(*))
FROM   user_objects
WHERE  object_name IN ('DH_ASSET_STATUS_V', 'DH_OPEN_ANOMALIES_V', 'DH_SET_VALVE', 'DH_SET_IN_SERVICE') AND status = 'VALID';

INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'A15', 'Teardown and fresh install',
       DECODE('&t_clean', 'Y', 'done, no invalid objects', 'skipped (run with clean)'),
       DECODE('&t_clean', 'Y', CASE WHEN COUNT(*) = 0 THEN 'done, no invalid objects' ELSE COUNT(*) || ' invalid objects' END,
                               'skipped (run with clean)')
FROM   user_objects WHERE status = 'INVALID';

-- -----------------------------------------------------------------------------
-- 4. Act 2 in the rehearsal state (B1)
-- -----------------------------------------------------------------------------
PROMPT == 4. Act 2 checks in the rehearsal state (B1)
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'B1', 'q0 cold buildings (rehearsal state)', '&e_base', dh_test.cold_buildings FROM dual;
DECLARE
  l_ddl CLOB;
BEGIN
  l_ddl := DBMS_METADATA.GET_DDL('PROPERTY_GRAPH', 'DH_NETWORK');
  dh_test.add_result('B1', 'q0b GET_DDL of DH_NETWORK', 'yes',
                     CASE WHEN DBMS_LOB.INSTR(UPPER(l_ddl), 'PROPERTY GRAPH') > 0 THEN 'yes' ELSE 'no DDL' END);
EXCEPTION WHEN OTHERS THEN
  dh_test.add_result('B1', 'q0b GET_DDL of DH_NETWORK', 'yes', 'error: ' || SQLERRM);
END;
/
INSERT INTO dh_test_results (id, check_name, expected, actual)
WITH downstream (asset_id) AS (
  SELECT to_asset FROM dh_pipes WHERE from_asset = 'PS-04' AND valve_state = 'OPEN'
  UNION ALL
  SELECT p.to_asset FROM dh_pipes p JOIN downstream d ON p.from_asset = d.asset_id WHERE p.valve_state = 'OPEN'
), r AS (
  SELECT DISTINCT d.asset_id FROM downstream d JOIN dh_assets a ON a.asset_id = d.asset_id WHERE a.asset_type = 'BUILDING'
), g AS (
  SELECT DISTINCT b_id FROM GRAPH_TABLE (dh_network
    MATCH (ps IS asset WHERE ps.asset_id = 'PS-04') -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
          (b IS asset WHERE b.asset_type = 'BUILDING')
    COLUMNS (b.asset_id AS b_id))
)
SELECT 'B1', 'q1 recursive SQL / q2 GRAPH_TABLE / differences', '40 / 40 / 0',
       (SELECT COUNT(*) FROM r) || ' / ' || (SELECT COUNT(*) FROM g) || ' / '
       || ((SELECT COUNT(*) FROM (SELECT asset_id FROM r MINUS SELECT b_id FROM g))
         + (SELECT COUNT(*) FROM (SELECT b_id FROM g MINUS SELECT asset_id FROM r)))
FROM   dual;
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'B1', 'q7 path heat plant -> hospital: steps', '4', TO_CHAR(COUNT(*))
FROM   GRAPH_TABLE (dh_network
         MATCH (pl IS asset WHERE pl.asset_type = 'PLANT')
               -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
               (h IS asset WHERE h.building_type = 'HOSPITAL' AND h.asset_id LIKE 'B-05%')
         ONE ROW PER STEP (v1, e, v2)
         COLUMNS (e.pipe_id AS pipe_id));
COMMIT;

-- -----------------------------------------------------------------------------
-- 5. Simulation (C1-C6), with the Act 2/3 and agent checks in the live state
-- -----------------------------------------------------------------------------
PROMPT == 5. Simulation tests (about 9 minutes, the job runs every 30 seconds)
COLUMN t0 NEW_VALUE t0 NOPRINT
SELECT TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF TZH:TZM') AS t0 FROM dual;

-- C1: one step by hand
DECLARE
  l_n0 NUMBER;
  l_n1 NUMBER;
  l_log NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_n0 FROM dh_telemetry WHERE source = 'SIMULATED';
  dh_job_tick;
  SELECT COUNT(*) INTO l_n1 FROM dh_telemetry WHERE source = 'SIMULATED';
  SELECT COUNT(*) INTO l_log FROM dh_job_log WHERE logged_at > TO_TIMESTAMP_TZ('&t0', 'YYYY-MM-DD HH24:MI:SS.FF TZH:TZM');
  dh_test.add_result('C1', 'One step by hand: new SIMULATED readings', '250', TO_CHAR(l_n1 - l_n0));
  dh_test.add_result('C1', 'Messages in DH_JOB_LOG', '0', TO_CHAR(l_log));
END;
/

-- C2: the job
EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')
PROMPT    C2: job enabled, waiting 75 seconds ...
EXEC DBMS_SESSION.SLEEP(75)
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C2', 'Job runs since the start (SUCCEEDED / other)', 'yes',
       CASE WHEN COUNT(CASE WHEN status = 'SUCCEEDED' THEN 1 END) >= 2 AND COUNT(CASE WHEN status <> 'SUCCEEDED' THEN 1 END) = 0
            THEN 'yes' ELSE COUNT(CASE WHEN status = 'SUCCEEDED' THEN 1 END) || ' / ' || COUNT(CASE WHEN status <> 'SUCCEEDED' THEN 1 END) END
FROM   user_scheduler_job_run_details
WHERE  job_name = 'DH_TICK_JOB' AND log_date > TO_TIMESTAMP_TZ('&t0', 'YYYY-MM-DD HH24:MI:SS.FF TZH:TZM');
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C2', 'Messages in DH_JOB_LOG', '0', TO_CHAR(COUNT(*))
FROM   dh_job_log WHERE logged_at > TO_TIMESTAMP_TZ('&t0', 'YYYY-MM-DD HH24:MI:SS.FF TZH:TZM');

-- C3: trip PS-04
EXEC dh_device_sim.trip('PS-04')
PROMPT    C3: PS-04 tripped, waiting 150 seconds ...
EXEC DBMS_SESSION.SLEEP(150)
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C3', 'PS-04 state', 'STOPPED', MAX(pump_state) FROM dh_sim_state WHERE asset_id = 'PS-04';
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C3', 'Cold buildings after the trip', '&e_trip', dh_test.cold_buildings FROM dual;
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C3', 'Apartments without heat', '3160', TO_CHAR(SUM(apartments))
FROM   dh_assets WHERE asset_type = 'BUILDING' AND health_status = 'ALARM';
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C3', 'PS-04 THRESHOLD ALARM (flow or pressure)', 'yes', CASE WHEN COUNT(*) > 0 THEN 'yes' ELSE 'no' END
FROM   dh_anomalies
WHERE  asset_id = 'PS-04' AND anomaly_type = 'THRESHOLD' AND severity = 'ALARM' AND status <> 'CLOSED';

-- B1 in the live state
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'B1', 'q3 PS-04 explains cold buildings (live)', '40', TO_CHAR(COUNT(DISTINCT cold_building))
FROM   GRAPH_TABLE (dh_network
         MATCH (an IS anomaly WHERE an.status <> 'CLOSED')
               -[IS detected_on]-> (s IS asset WHERE s.asset_id = 'PS-04')
               -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
               (b IS asset WHERE b.asset_type = 'BUILDING' AND b.health_status = 'ALARM')
         COLUMNS (b.asset_id AS cold_building));
COMMIT;
-- q8 runs Personalized PageRank (DBMS_OGA). Graph algorithms do not run inside
-- an open transaction (ORA-40972), so the function is called in PL/SQL after
-- a COMMIT and not inside an INSERT ... SELECT.
DECLARE
  l_j   CLOB;
  l_val VARCHAR2(4000);
BEGIN
  COMMIT;
  l_j := agent_find_root_cause();
  SELECT JSON_VALUE(l_j, '$.cold_buildings') || ' / ' || JSON_VALUE(l_j, '$.incidents[0].root_cause_asset')
         || ' / ' || NVL(JSON_VALUE(l_j, '$.personalized_pagerank_top5[0].asset_id'),
                         'note: ' || JSON_VALUE(l_j, '$.personalized_pagerank_note.error'))
  INTO   l_val
  FROM   dual;
  dh_test.add_result('B1', 'q8 root cause JSON: cold / first incident / PageRank top', '45 / PS-04 / PS-04', l_val);
EXCEPTION WHEN OTHERS THEN
  dh_test.add_result('B1', 'q8 root cause JSON: cold / first incident / PageRank top', '45 / PS-04 / PS-04',
                     'error: ' || SUBSTR(SQLERRM, 1, 200));
END;
/

-- B2: graph algorithms
-- DBMS_OGA runs through dynamic SQL in PL/SQL (SELECT ... INTO), as in
-- 07_agent_api.sql. An INSERT ... SELECT FROM GRAPH_TABLE (DBMS_OGA...) can
-- end the session (ORA-17008 closed connection). Graph algorithms do not run
-- inside an open transaction (ORA-40972), so each check starts with a COMMIT.
-- A failing check is written as 'error: ...' and the run goes on.
DECLARE
  PROCEDURE check_oga (p_check IN VARCHAR2, p_expected IN VARCHAR2, p_sql IN VARCHAR2) IS
    l_val VARCHAR2(4000);
  BEGIN
    COMMIT;
    EXECUTE IMMEDIATE p_sql INTO l_val;
    dh_test.add_result('B2', p_check, p_expected, l_val);
  EXCEPTION WHEN OTHERS THEN
    dh_test.add_result('B2', p_check, p_expected, 'error: ' || SUBSTR(SQLERRM, 1, 200));
  END check_oga;
BEGIN
  check_oga('PageRank top 4 (equal scores)', 'PS-01, PS-04, PS-07, PS-09', q'~
    SELECT LISTAGG(asset_id, ', ') WITHIN GROUP (ORDER BY asset_id)
    FROM  (SELECT asset_id
           FROM   GRAPH_TABLE (DBMS_OGA.PAGERANK(dh_dependency, PROPERTY(VERTEX OUTPUT rank), 100, 1e-6, 0.85d, FALSE)
                    MATCH (v IS asset WHERE v.asset_type IN ('PUMP_STATION', 'SUBSTATION'))
                    COLUMNS (v.asset_id AS asset_id, v.rank AS rank))
           ORDER  BY rank DESC FETCH FIRST 4 ROWS ONLY)~');

  dh_whatif.set_scenario(p_out_of_service => 'PS-04');
  check_oga('WCC: buildings cut off without PS-04', '40', q'~
    SELECT TO_CHAR(NVL(SUM(nb), 0))
    FROM  (SELECT comp, SUM(CASE WHEN asset_type = 'BUILDING' THEN 1 ELSE 0 END) nb,
                  SUM(CASE WHEN asset_type = 'PLANT' THEN 1 ELSE 0 END) np
           FROM   GRAPH_TABLE (DBMS_OGA.WCC(dh_live_network, PROPERTY(VERTEX OUTPUT comp))
                    MATCH (a IS asset) COLUMNS (a.asset_type AS asset_type, a.comp AS comp))
           GROUP  BY comp)
    WHERE  np = 0~');

  dh_whatif.set_scenario(p_out_of_service => 'PS-04', p_open_valves => 'BYP-1');
  check_oga('WCC: buildings cut off without PS-04, BYP-1 open', '20', q'~
    SELECT TO_CHAR(NVL(SUM(nb), 0))
    FROM  (SELECT comp, SUM(CASE WHEN asset_type = 'BUILDING' THEN 1 ELSE 0 END) nb,
                  SUM(CASE WHEN asset_type = 'PLANT' THEN 1 ELSE 0 END) np
           FROM   GRAPH_TABLE (DBMS_OGA.WCC(dh_live_network, PROPERTY(VERTEX OUTPUT comp))
                    MATCH (a IS asset) COLUMNS (a.asset_type AS asset_type, a.comp AS comp))
           GROUP  BY comp)
    WHERE  np = 0~');
  dh_whatif.clear;

  check_oga('Bellman-Ford: HP-A to PS-04 = length of pipe P-0003', 'yes', q'~
    SELECT CASE WHEN ROUND(MAX(g.dist)) = MAX(p.length_m) THEN 'yes'
                ELSE 'no: ' || ROUND(MAX(g.dist)) || ' <> ' || MAX(p.length_m) END
    FROM   GRAPH_TABLE (DBMS_OGA.BELLMAN_FORD(
                          dh_live_network,
                          JSON('{"GRAPH_OWNER":"&_USER","GRAPH_NAME":"DH_LIVE_NETWORK","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"HP-A"}}'),
                          PROPERTY(EDGE INPUT length_m DEFAULT ON NULL 0),
                          PROPERTY(VERTEX OUTPUT dist))
             MATCH (v IS asset WHERE v.asset_id = 'PS-04')
             COLUMNS (v.dist AS dist)) g
    CROSS  JOIN (SELECT length_m FROM dh_pipes WHERE pipe_id = 'P-0003') p~');
EXCEPTION WHEN OTHERS THEN
  dh_whatif.clear;
  dh_test.add_result('B2', 'Graph algorithm checks', 'yes', 'error: ' || SUBSTR(SQLERRM, 1, 200));
END;
/

-- B3: every agent tool returns JSON without an "error" key
DECLARE
  TYPE t_calls IS TABLE OF VARCHAR2(200);
  l_calls t_calls := t_calls(
    'agent_network_status()', 'agent_active_anomalies(''WARNING'')', 'agent_find_root_cause()',
    'agent_find_root_cause(''&e_ps04'')', 'agent_impact_analysis(''PS-04'')', 'agent_what_if(''PS-04'', ''BYP-1'')',
    'agent_predict_failures(240)', 'agent_critical_assets(5)', 'agent_asset_details(''PS-04'')',
    'agent_maintenance_history(''PS-04'')',
    'agent_create_work_order(''PS-04'', ''P4'', ''TEST from test_all.sql'')');
  l_ok VARCHAR2(400);
BEGIN
  FOR i IN 1 .. l_calls.COUNT LOOP
    BEGIN
      EXECUTE IMMEDIATE
        'SELECT CASE WHEN j IS JSON AND NOT JSON_EXISTS(j, ''$.error'') THEN ''yes'' ELSE ''no: '' || DBMS_LOB.SUBSTR(j, 150, 1) END'
        || ' FROM (SELECT ' || l_calls(i) || ' AS j FROM dual)'
        INTO l_ok;
    EXCEPTION WHEN OTHERS THEN
      l_ok := 'error: ' || SUBSTR(SQLERRM, 1, 200);
    END;
    dh_test.add_result('B3', l_calls(i), 'yes', l_ok);
  END LOOP;
  DELETE FROM dh_work_orders WHERE title = 'TEST from test_all.sql';
  COMMIT;
END;
/
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'B3', 'agent_predict_failures after the trip: assets', 'PS-08',
       NVL(SUBSTRB(LISTAGG(DISTINCT asset_id, ', ' ON OVERFLOW TRUNCATE) WITHIN GROUP (ORDER BY asset_id), 1, 4000), '-')
FROM   JSON_TABLE(agent_predict_failures(240), '$.predictions[*]' COLUMNS (asset_id VARCHAR2(20) PATH '$.asset_id'));

-- C4: bypass
EXEC dh_set_valve('BYP-1', 'OPEN')
PROMPT    C4: BYP-1 open, waiting 105 seconds ...
EXEC DBMS_SESSION.SLEEP(105)
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C4', 'Cold buildings with BYP-1 open', '&e_bypass', dh_test.cold_buildings FROM dual;

-- C5: repair, bypass closed
EXEC dh_device_sim.repair('PS-04')
EXEC dh_set_valve('BYP-1', 'CLOSED')
PROMPT    C5: PS-04 repaired, BYP-1 closed, waiting 105 seconds ...
EXEC DBMS_SESSION.SLEEP(105)
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C5', 'Cold buildings after the repair', '&e_base', dh_test.cold_buildings FROM dual;
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C5', 'PS-04 state', 'RUNNING', MAX(pump_state) FROM dh_sim_state WHERE asset_id = 'PS-04';

-- C6: reset before a rehearsal
@@stop_tick_job.sql
@@apex_cleanup.sql
EXEC dh_sim.reset_state
EXEC dh_sim.backfill
EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')
PROMPT    C6: reset and new history, waiting 45 seconds ...
EXEC DBMS_SESSION.SLEEP(45)
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C6', 'Status after the reset', 'pumps not running: - | open bypass: - | wear PS-04 4.40',
       REGEXP_SUBSTR(dh_device_sim.status, '^pumps not running: [^|]*\| open bypass: [^|]*\|') || ' wear PS-04 '
       || REGEXP_SUBSTR(dh_device_sim.status, 'PS-04 ([0-9.]+)', 1, 1, NULL, 1)
FROM   dual;
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C6', 'Open anomalies per asset after the reset', 'PS-04:4, PS-08:1, SS-09.3:2',
       SUBSTRB(LISTAGG(asset_id || ':' || n, ', ' ON OVERFLOW TRUNCATE) WITHIN GROUP (ORDER BY asset_id), 1, 4000)
FROM  (SELECT asset_id, COUNT(*) n FROM dh_anomalies WHERE status <> 'CLOSED' GROUP BY asset_id);
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C6', 'Cold buildings after the reset', '&e_base', dh_test.cold_buildings FROM dual;
INSERT INTO dh_test_results (id, check_name, expected, actual)
SELECT 'C6', 'Work orders left from the test', '0', TO_CHAR(COUNT(*)) FROM dh_work_orders WHERE created_by <> 'SEED';
COMMIT;

-- Job back to the state before the test
BEGIN
  IF '&s_job' = 'FALSE' THEN
    DBMS_SCHEDULER.DISABLE('DH_TICK_JOB', force => TRUE);   -- lets a running tick finish
  END IF;
END;
/

-- -----------------------------------------------------------------------------
-- 6. Results
-- -----------------------------------------------------------------------------
UPDATE dh_test_results
SET    result = CASE WHEN NVL(expected, '~') = NVL(actual, '~') OR expected LIKE 'skipped%' AND actual = expected
                     THEN 'PASS' ELSE 'FAIL' END;
COMMIT;

-- Result list in German. The checks are stored in English; DH_TEST.TXT and
-- DH_TEST.VAL translate them for the display.
COLUMN h_check    NEW_VALUE h_check    NOPRINT
COLUMN h_expected NEW_VALUE h_expected NOPRINT
COLUMN h_actual   NEW_VALUE h_actual   NOPRINT
COLUMN h_result   NEW_VALUE h_result   NOPRINT
COLUMN h_checks   NEW_VALUE h_checks   NOPRINT
COLUMN h_passed   NEW_VALUE h_passed   NOPRINT
COLUMN h_failed   NEW_VALUE h_failed   NOPRINT
COLUMN h_step     NEW_VALUE h_step     NOPRINT
COLUMN p_results  NEW_VALUE p_results  NOPRINT
COLUMN p_summary  NEW_VALUE p_summary  NOPRINT
COLUMN p_total    NEW_VALUE p_total    NOPRINT
COLUMN p_note1    NEW_VALUE p_note1    NOPRINT
COLUMN p_note2    NEW_VALUE p_note2    NOPRINT
SELECT dh_test.txt('#h_check') AS h_check, dh_test.txt('#h_expected') AS h_expected,
       dh_test.txt('#h_actual') AS h_actual, dh_test.txt('#h_result') AS h_result,
       dh_test.txt('#h_checks') AS h_checks, dh_test.txt('#h_passed') AS h_passed,
       dh_test.txt('#h_failed') AS h_failed, dh_test.txt('#h_step') AS h_step,
       dh_test.txt('#p_results') AS p_results, dh_test.txt('#p_summary') AS p_summary,
       dh_test.txt('#p_total') AS p_total, dh_test.txt('#p_note1') AS p_note1, dh_test.txt('#p_note2') AS p_note2
FROM   dual;

PROMPT
PROMPT &p_results
COLUMN id         FORMAT A4  HEADING 'ID'
COLUMN check_name FORMAT A55 WORD_WRAPPED HEADING '&h_check'
COLUMN expected   FORMAT A45 WORD_WRAPPED HEADING '&h_expected'
COLUMN actual     FORMAT A45 WORD_WRAPPED HEADING '&h_actual'
COLUMN result     FORMAT A8  HEADING '&h_result'
SELECT id, dh_test.txt(check_name) AS check_name, dh_test.val(expected) AS expected,
       dh_test.val(actual) AS actual, dh_test.txt(result) AS result
FROM   dh_test_results
ORDER  BY seq;

PROMPT
PROMPT &p_summary
COLUMN checks      FORMAT 999 HEADING '&h_checks'
COLUMN step_result FORMAT A8  HEADING '&h_step'
SELECT id, COUNT(*) AS checks,
       dh_test.txt(CASE WHEN COUNT(CASE WHEN result = 'FAIL' THEN 1 END) = 0 THEN 'PASS' ELSE 'FAIL' END) AS step_result
FROM   dh_test_results
GROUP  BY id
ORDER  BY SUBSTR(id, 1, 1), TO_NUMBER(SUBSTR(id, 2));

PROMPT
PROMPT &p_total
COLUMN passed FORMAT 999 HEADING '&h_passed'
COLUMN failed FORMAT 999 HEADING '&h_failed'
SELECT COUNT(*) AS checks,
       COUNT(CASE WHEN result = 'PASS' THEN 1 END) AS passed,
       COUNT(CASE WHEN result = 'FAIL' THEN 1 END) AS failed
FROM   dh_test_results;
PROMPT &p_note1
PROMPT &p_note2
SET FEEDBACK ON
