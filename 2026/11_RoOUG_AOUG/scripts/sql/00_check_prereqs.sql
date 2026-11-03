-- =============================================================================
-- 00_check_prereqs.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-11-03
--
-- Run as the demo user (OGBEMEA2026) in Oracle Autonomous AI Database 26ai.
-- Checks database version, graph packages and privileges before installing.
-- Idempotent: the smoke-test objects are dropped before and after the test.
-- =============================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200

PROMPT == Database version
SELECT banner_full FROM v$version;

PROMPT == Graph algorithm packages (needed for Act 3; pure SQL/PGQ works without them)
SELECT owner, object_name, object_type
FROM   all_objects
WHERE  object_name IN ('DBMS_OGA', 'DBMS_GAF')
AND    object_type = 'PACKAGE';

PROMPT == EXECUTE on DBMS_CRYPTO (needed to store secrets encrypted; else run 00_admin_setup.sql again)
SELECT table_name AS package_name, privilege FROM user_tab_privs WHERE table_name = 'DBMS_CRYPTO';

PROMPT == Privileges of the current user
SELECT privilege FROM session_privs
WHERE  privilege IN ('CREATE PROPERTY GRAPH', 'CREATE TABLE', 'CREATE VIEW', 'CREATE PROCEDURE',
                     'CREATE JOB', 'CREATE ANY CONTEXT')
ORDER  BY privilege;

PROMPT == Quick SQL/PGQ smoke test
DECLARE
  l_n NUMBER;
  PROCEDURE cleanup IS
  BEGIN
    BEGIN EXECUTE IMMEDIATE 'DROP PROPERTY GRAPH dh_smoke_g'; EXCEPTION WHEN OTHERS THEN NULL; END;
    EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS dh_smoke_e PURGE';
    EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS dh_smoke_v PURGE';
  END cleanup;
BEGIN
  cleanup;   -- leftovers of an earlier, interrupted run
  EXECUTE IMMEDIATE 'CREATE TABLE dh_smoke_v (id NUMBER PRIMARY KEY)';
  EXECUTE IMMEDIATE 'CREATE TABLE dh_smoke_e (id NUMBER PRIMARY KEY, s NUMBER REFERENCES dh_smoke_v, d NUMBER REFERENCES dh_smoke_v)';
  EXECUTE IMMEDIATE 'INSERT INTO dh_smoke_v VALUES (1)';
  EXECUTE IMMEDIATE 'INSERT INTO dh_smoke_v VALUES (2)';
  EXECUTE IMMEDIATE 'INSERT INTO dh_smoke_e VALUES (1, 1, 2)';
  EXECUTE IMMEDIATE 'CREATE PROPERTY GRAPH dh_smoke_g VERTEX TABLES (dh_smoke_v KEY (id) LABEL v) '
                 || 'EDGE TABLES (dh_smoke_e KEY (id) SOURCE KEY (s) REFERENCES dh_smoke_v (id) '
                 || 'DESTINATION KEY (d) REFERENCES dh_smoke_v (id) LABEL e)';
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM GRAPH_TABLE (dh_smoke_g MATCH (a) -[x]-> (b) COLUMNS (a.id AS a_id))' INTO l_n;
  DBMS_OUTPUT.PUT_LINE('SQL/PGQ OK, matches: ' || l_n);
  BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM GRAPH_TABLE (DBMS_OGA.WCC(dh_smoke_g, PROPERTY(VERTEX OUTPUT c)) '
                   || 'MATCH (a) COLUMNS (a.c AS c))' INTO l_n;
    DBMS_OUTPUT.PUT_LINE('DBMS_OGA OK, vertices with component: ' || l_n);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('DBMS_OGA NOT AVAILABLE: ' || SQLERRM || ' -> graph algorithms (PageRank, WCC) not available; SQL/PGQ pattern queries still work');
  END;
  cleanup;
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Smoke test failed: ' || SQLERRM);
  cleanup;
END;
/

PROMPT == APEX version (Graph Visualization plug-in: use the GitHub branch that matches, e.g. 26.1 or 24.2)
SELECT version_no FROM apex_release;

-- -----------------------------------------------------------------------------
-- Optional: APEX upgrade status (run as ADMIN, not as the demo user)
-- -----------------------------------------------------------------------------
-- On Autonomous AI Database, Oracle rolls out new APEX releases per region,
-- usually 2-5 weeks after they appear on oracle.com. Until then the instance
-- shows "System is up-to-date" and there is no button to upgrade. Patch Set
-- Bundles (e.g. 24.2.17) are applied automatically during maintenance.
--
-- The query needs ADMIN or APEX_ADMINISTRATOR_ROLE:
--
--   SELECT APEX_INSTANCE_ADMIN.get_parameter('UPGRADE_STATUS')  AS upgrade_status,
--          APEX_INSTANCE_ADMIN.get_parameter('UPGRADE_VERSION') AS upgrade_version,
--          APEX_INSTANCE_ADMIN.get_parameter('UPGRADE_DATE')    AS upgrade_date
--   FROM   dual;
--
-- UPGRADE_STATUS:
--   UP-TO-DATE  no newer release in this region yet; stay on the current
--               version (24.2 and 26.1 both work for the demo: plug-in from
--               the matching branch; the demo workspace runs 26.1)
--   SCHEDULED   a new release is available; UPGRADE_VERSION shows which,
--               UPGRADE_DATE when Oracle applies it automatically (45-day
--               window by default, 90 days if deferred)
--   RUNNING     the upgrade is in progress
--
-- To upgrade right away when SCHEDULED: APEX Administration Services >
-- Available Updates > Upgrade Now, or as ADMIN:
--
--   BEGIN
--     APEX_INSTANCE_ADMIN.set_parameter('UPGRADE_STATUS', 'RUN');
--     COMMIT;
--   END;
--   /
--
-- After an upgrade, re-import the Graph Visualization plug-in and the two
-- helper scripts from the matching branch (scripts/apex/BUILD.md).
-- Docs: https://docs.oracle.com/en/cloud/paas/atp-cloud/atpug/apex-apply-defer-updates.html
