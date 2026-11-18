--------------------------------------------------------------------------------
-- File       : 00_create_user.sql
-- Project    : DOAG 2026 - "Spatial AI in Python: Unlocking Machine Learning
--              for Geospatial Intelligence" (workshop)
-- Purpose    : Creates a workshop user and grants every privilege the
--              workshop needs:
--                - Spatial (SDO_GEOMETRY tables, spatial indexes, SQL)
--                - OML4Py in OML Notebooks, including Spatial AI (oraclesai,
--                  installed automatically together with OML4Py)
--                - Spatial Studio (built-in tool of Autonomous AI Database)
--                - Database Actions (SQL worksheet, data load)
--                - DBMS_CLOUD (load open data from Object Storage or URLs)
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as ADMIN, in folder scripts/sql. The user name is
--              not fixed: it is the first script argument, taken from the
--              environment variable WORKSHOP_USER:
--                sql admin@<tns_alias> @00_create_user.sql %WORKSHOP_USER%
--              The script then asks for the user name and shows the first
--              argument as default: press Enter to accept it. Without an
--              argument, type the name.
-- Re-runnable: yes. An existing user is kept, the privileges are granted
--              again. Run it once per workshop user.
-- Log        : log/sql/00_create_user.log in the project folder,
--              overwritten on every run
-- Sources    : Set Up Spatial Studio Users and Privileges
--              https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adstu/set-spatial-studio-users-and-privileges.html
--              Create and Update User Accounts for Oracle Machine Learning
--              Components on Autonomous AI Database
--              https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/manage-users-oml.html
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

-- Workshop user name. The first script argument (from WORKSHOP_USER) is
-- optional: if it is missing, &1 is defined as empty instead of SQLcl
-- asking "Enter value for 1".
SET TERMOUT OFF
COLUMN 1 NEW_VALUE 1 NOPRINT
SELECT NULL AS "1" FROM dual WHERE 1 = 0;
COLUMN user_hint NEW_VALUE user_hint NOPRINT
SELECT CASE WHEN q'[&1]' IS NULL THEN NULL
            ELSE ' [&1, press Enter to accept]' END AS user_hint
FROM   dual;
SET TERMOUT ON

PROMPT
PROMPT Name of the workshop database user to create:
PROMPT   letter first, then letters, digits or _ (max. 128), e.g. WS_TEST
ACCEPT workshop_user CHAR DEFAULT '&1' PROMPT 'Database user name&user_hint: '

-- Spatial Studio role of the user:
--   SPATIAL_AUTHOR   = create datasets, projects and analyses (attendees)
--   SPATIAL_ADMIN    = additionally administer Spatial Studio (instructors)
--   SPATIAL_CONSUMER = read-only
DEFINE spatial_role = SPATIAL_AUTHOR

-- Y = grant access to SDO_GCDR geocoding and routing (section 5, optional)
DEFINE enable_eloc = Y

SPOOL ../../log/sql/00_create_user.log REPLACE

PROMPT
PROMPT === 00 Create workshop user &workshop_user ===

-- Run as ADMIN only, and check the user name before anything is created
BEGIN
  IF SYS_CONTEXT('USERENV', 'SESSION_USER') <> 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'This script must run as ADMIN, not as '
                                    || SYS_CONTEXT('USERENV', 'SESSION_USER') || '.');
  END IF;

  IF TRIM('&workshop_user') IS NULL THEN
    RAISE_APPLICATION_ERROR(-20002, 'No user name given. Type it at the prompt or pass '
                                    || 'it as first argument, e.g. @00_create_user.sql %WORKSHOP_USER%.');
  END IF;

  -- Simple, unquoted name: letter first, then letters, digits, _ (max 128)
  IF NOT REGEXP_LIKE('&workshop_user', '^[A-Za-z][A-Za-z0-9_]{0,127}$') THEN
    RAISE_APPLICATION_ERROR(-20003, 'Invalid user name "&workshop_user": use a letter '
                                    || 'first, then letters, digits or _.');
  END IF;

  IF UPPER('&workshop_user') IN ('ADMIN', 'SYS', 'SYSTEM', 'PUBLIC', 'OML$PROXY',
                                 'SPATIAL$PROXY_USER') THEN
    RAISE_APPLICATION_ERROR(-20004, 'User name &workshop_user is reserved.');
  END IF;
END;
/

-- Ask for the password without echoing it. Autonomous AI Database rules:
-- 12 to 30 characters, at least one upper-case letter, one lower-case letter
-- and one digit, no double quote, not the user name.
ACCEPT workshop_pwd CHAR PROMPT 'Password for &workshop_user: ' HIDE

--------------------------------------------------------------------------------
-- 1. User
--------------------------------------------------------------------------------
-- Tablespace DATA is predefined on Autonomous AI Database.
CREATE USER IF NOT EXISTS &workshop_user
  IDENTIFIED BY "&workshop_pwd"
  DEFAULT TABLESPACE data
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON data;

-- On a re-run: make sure the quota is set (the password stays unchanged)
ALTER USER &workshop_user QUOTA UNLIMITED ON data;

UNDEFINE workshop_pwd

--------------------------------------------------------------------------------
-- 2. Roles and system privileges (Spatial, Spatial Studio)
--------------------------------------------------------------------------------
-- DB_DEVELOPER_ROLE (23ai and later) contains, among others, CREATE SESSION,
-- TABLE, VIEW, SEQUENCE, PROCEDURE, TYPE, TRIGGER and MINING MODEL. This
-- covers tables with SDO_GEOMETRY and spatial indexes (MDSYS.SPATIAL_INDEX_V2
-- creates tables and sequences in the user's schema).
GRANT DB_DEVELOPER_ROLE TO &workshop_user;

-- Spatial Studio needs these system privileges for SPATIAL_AUTHOR and
-- SPATIAL_ADMIN (see "Set Up Spatial Studio Users and Privileges").
-- Granted directly, they also apply in stored PL/SQL and in scheduler jobs.
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TYPE, CREATE SYNONYM, CREATE TRIGGER
   TO &workshop_user;

--------------------------------------------------------------------------------
-- 3. OML4Py, Spatial AI and Spatial Studio (one by one, so a missing role
--    or proxy user does not stop everything)
--------------------------------------------------------------------------------
DECLARE
  TYPE t_stmts IS TABLE OF VARCHAR2(400);
  l_user  CONSTANT VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(UPPER('&workshop_user'));
  l_role  CONSTANT VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(UPPER('&spatial_role'));
  l_stmts t_stmts := t_stmts(
    -- OML Notebooks with the Python interpreter (OML4Py). Spatial AI
    -- (oraclesai) is installed automatically with OML4Py, it needs no
    -- separate grant. This is what the "OML" switch in Database Actions >
    -- Database Users does.
    'GRANT OML_DEVELOPER TO ' || l_user,
    'GRANT DWROLE TO '        || l_user,
    'ALTER USER '             || l_user || ' GRANT CONNECT THROUGH OML$PROXY',
    -- Spatial Studio: role and sign-in through the Spatial Studio proxy user
    'GRANT ' || l_role || ' TO ' || l_user,
    'ALTER USER '             || l_user || ' GRANT CONNECT THROUGH "SPATIAL$PROXY_USER"',
    -- Load open data (CSV, GeoJSON, ...) from Object Storage or public URLs
    'GRANT EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD TO ' || l_user,
    -- Stage downloaded files in the database directory
    'GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO '  || l_user
  );
BEGIN
  FOR i IN 1 .. l_stmts.COUNT LOOP
    BEGIN
      EXECUTE IMMEDIATE l_stmts(i);
      DBMS_OUTPUT.PUT_LINE('OK      ' || l_stmts(i));
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('WARNING ' || l_stmts(i) || ' -> ' || SQLERRM);
    END;
  END LOOP;
END;
/

--------------------------------------------------------------------------------
-- 4. Enable Database Actions (SQL worksheet, Data Load, single sign-on to
--    Spatial Studio and OML)
--------------------------------------------------------------------------------
BEGIN
  ORDS_ADMIN.ENABLE_SCHEMA(
    p_enabled             => TRUE,
    p_schema              => UPPER('&workshop_user'),
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => LOWER('&workshop_user'),
    p_auto_rest_auth      => TRUE);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('OK      ORDS_ADMIN.ENABLE_SCHEMA(' || UPPER('&workshop_user') || ')');
END;
/

--------------------------------------------------------------------------------
-- 5. Geocoding and routing with SDO_GCDR (optional, Autonomous AI Database
--    only, ADMIN only)
--------------------------------------------------------------------------------
BEGIN
  IF UPPER('&enable_eloc') = 'Y' THEN
    SDO_GCDR.ELOC_GRANT_ACCESS(UPPER('&workshop_user'));
    DBMS_OUTPUT.PUT_LINE('OK      SDO_GCDR.ELOC_GRANT_ACCESS(' || UPPER('&workshop_user') || ')');
  ELSE
    DBMS_OUTPUT.PUT_LINE('SKIPPED SDO_GCDR.ELOC_GRANT_ACCESS (enable_eloc = N)');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('WARNING SDO_GCDR.ELOC_GRANT_ACCESS -> ' || SQLERRM);
END;
/

--------------------------------------------------------------------------------
-- 6. Checks
--------------------------------------------------------------------------------
PROMPT
PROMPT --- User
SELECT username, account_status, default_tablespace
FROM   dba_users
WHERE  username = UPPER('&workshop_user');

PROMPT --- Roles (expected: DB_DEVELOPER_ROLE, DWROLE, OML_DEVELOPER, &spatial_role)
SELECT granted_role
FROM   dba_role_privs
WHERE  grantee = UPPER('&workshop_user')
ORDER  BY granted_role;

PROMPT --- System privileges (granted directly)
SELECT privilege
FROM   dba_sys_privs
WHERE  grantee = UPPER('&workshop_user')
ORDER  BY privilege;

PROMPT --- Object privileges
SELECT owner || '.' || table_name AS object_name, privilege
FROM   dba_tab_privs
WHERE  grantee = UPPER('&workshop_user')
ORDER  BY 1, 2;

PROMPT --- Proxy users (expected: OML$PROXY, SPATIAL$PROXY_USER)
SELECT proxy
FROM   proxy_users
WHERE  client = UPPER('&workshop_user')
ORDER  BY proxy;

PROMPT
PROMPT Done. &workshop_user can now sign in to
PROMPT   - Oracle Machine Learning (Python interpreter with OML4Py and Spatial AI)
PROMPT   - Spatial Studio (role &spatial_role)
PROMPT   - Database Actions (SQL worksheet, Data Load)
PROMPT Any WARNING above means a grant is missing: check it before the workshop.

SPOOL OFF
