-- =============================================================================
-- 00_admin_setup.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-10-30
--
-- Run once as ADMIN in Oracle Autonomous AI Database 26ai.
-- Creates the demo schema (default OGBEMEA2026), grants what the demo needs (incl.
-- EXECUTE on DBMS_CLOUD_AI, DBMS_CLOUD_AI_AGENT and DBMS_CRYPTO).
--
-- Prompts:
--   app_user           name of the demo user, default OGBEMEA2026 (Enter keeps it).
--                      The other scripts run as this user and use its name.
--   app_password       password for that user, typed hidden and never echoed
--                      (only used when the user does not exist yet; an existing
--                      user keeps its password, so just press Enter on a re-run)
--
-- Idempotent: safe to re-run. CREATE USER IF NOT EXISTS, grants and the ORDS
-- schema enablement can be repeated without errors.
--
-- -----------------------------------------------------------------------------
-- Outbound HTTPS: no network ACL needed
-- -----------------------------------------------------------------------------
-- The device simulation (06b_device_sim.sql) posts readings to the OCI IoT
-- Platform device endpoint, and the optional IoT pull (06_iot_sync.sql) calls
-- the IoT Data API and the OAuth token endpoint, all with APEX_WEB_SERVICE.
-- On Autonomous AI Database this works
-- without a user-defined network ACL (tested 2026-10-21 on 23.26.4.1.0:
-- APEX_WEB_SERVICE.MAKE_REST_REQUEST to an OCI endpoint returned HTTP 404,
-- i.e. the connection works). The test is printed at the end of this script.
--
-- DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE is therefore not part of the setup.
-- (In this database it fails for every new host with ORA-46215 / ORA-00913;
-- see Oracle Support. Only UTL_HTTP would need such an ACL.)
--
-- The IoT hosts are the same for both talks (Vienna, Bucharest); they depend on
-- the OCI region (here eu-frankfurt-1) and are configured later in DH_CONFIG:
--   Device host:   https://<domain-short-id>.device.iot.eu-frankfurt-1.oci.oraclecloud.com
--   IoT Data API:  https://<domain-group-short-id>.data.iot.eu-frankfurt-1.oci.oraclecloud.com  (optional pull)
--   OAuth token:   https://idcs-<unique-id>.identity.oraclecloud.com/oauth2/v1/token          (optional pull)
-- =============================================================================
SET VERIFY OFF
SET SERVEROUTPUT ON

ACCEPT app_user_in  CHAR DEFAULT 'OGBEMEA2026' PROMPT 'Demo user [OGBEMEA2026]: '
-- upper case, as stored in the data dictionary; DBMS_ASSERT rejects invalid names
COLUMN app_user NEW_VALUE app_user NOPRINT
SELECT UPPER(DBMS_ASSERT.SIMPLE_SQL_NAME(TRIM('&app_user_in'))) AS app_user FROM dual;
COLUMN app_user CLEAR
UNDEFINE app_user_in
ACCEPT app_password CHAR PROMPT 'Password for user &app_user (hidden; Enter if the user exists): ' HIDE

CREATE USER IF NOT EXISTS &app_user IDENTIFIED BY "&app_password"
  DEFAULT TABLESPACE data QUOTA UNLIMITED ON data;
UNDEFINE app_password

GRANT CONNECT, RESOURCE                         TO &app_user;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW TO &app_user;
GRANT CREATE PROCEDURE, CREATE SEQUENCE         TO &app_user;
GRANT CREATE PROPERTY GRAPH                     TO &app_user;
GRANT CREATE JOB                                TO &app_user;
GRANT CREATE ANY CONTEXT                        TO &app_user;   -- what-if scenarios (views read SYS_CONTEXT)

-- EXECUTE on the PL/SQL packages the demo uses:
--   DBMS_CLOUD                          cloud access (optional paths)
--   DBMS_CRYPTO                         secrets in DH_CONFIG stored encrypted
--   DBMS_CLOUD_AI, DBMS_CLOUD_AI_AGENT  Select AI and Select AI Agent
-- The owner is resolved first and the package is granted with its full name.
-- A plain "GRANT EXECUTE ON DBMS_CLOUD" goes through the public synonym, which
-- can fail with ORA-00980 (synonym translation is no longer valid). Each grant
-- reports its result; one failing grant does not stop the others.
PROMPT == EXECUTE on the PL/SQL packages
DECLARE
  PROCEDURE grant_exec (p_package IN VARCHAR2) IS
    l_owner VARCHAR2(128);
  BEGIN
    SELECT MAX(owner) KEEP (DENSE_RANK FIRST ORDER BY DECODE(owner, 'SYS', 2, 1))
    INTO   l_owner
    FROM   dba_objects
    WHERE  object_name = p_package AND object_type = 'PACKAGE'
    AND    owner IN ('SYS', 'C##CLOUD$SERVICE');
    IF l_owner IS NULL THEN
      DBMS_OUTPUT.PUT_LINE(RPAD(p_package, 22) || 'not found');
      RETURN;
    END IF;
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || l_owner || '.' || p_package || ' TO &app_user';
    DBMS_OUTPUT.PUT_LINE(RPAD(p_package, 22) || 'granted (owner ' || l_owner || ')');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(RPAD(p_package, 22) || 'FAILED: ' || SQLERRM);
  END grant_exec;
BEGIN
  grant_exec('DBMS_CLOUD');
  grant_exec('DBMS_CRYPTO');
  grant_exec('DBMS_CLOUD_AI');
  grant_exec('DBMS_CLOUD_AI_AGENT');
END;
/

-- Graph Studio / Database Actions access (optional, handy for checks)
BEGIN
  ORDS_ADMIN.ENABLE_SCHEMA(p_enabled => TRUE, p_schema => '&app_user', p_url_mapping_type => 'BASE_PATH',
                           p_url_mapping_pattern => LOWER('&app_user'), p_auto_rest_auth => TRUE);
END;
/
GRANT GRAPH_DEVELOPER TO &app_user;

PROMPT == Check: packages and privileges granted to &app_user
SELECT owner, table_name AS package_name, privilege
FROM   dba_tab_privs
WHERE  grantee = '&app_user' AND type = 'PACKAGE'
ORDER  BY table_name;

PROMPT == Optional check: outbound HTTPS via APEX_WEB_SERVICE (expect any HTTP status, e.g. 404)
PROMPT ==   connect as &app_user and run:
PROMPT ==   DECLARE l CLOB; BEGIN l := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
PROMPT ==     p_url => 'https://objectstorage.eu-frankfurt-1.oraclecloud.com/', p_http_method => 'GET');
PROMPT ==     DBMS_OUTPUT.PUT_LINE('HTTP status: ' || APEX_WEB_SERVICE.G_STATUS_CODE); END;
PROMPT ==   /

PROMPT Done. Next: connect as &app_user and run 00_check_prereqs.sql, then 00_install.sql
