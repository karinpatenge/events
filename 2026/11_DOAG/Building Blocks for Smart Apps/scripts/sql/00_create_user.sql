--------------------------------------------------------------------------------
-- File       : 00_create_user.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Creates the demo user and grants every privilege the demo
--              needs: JSON, Oracle Text, AI Vector Search, Spatial including
--              SDO_GCDR.ELOC_ROUTE, SQL Property Graph, RDF Graph,
--              DBMS_SCHEDULER, Select AI and Database Actions.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as ADMIN
--                sql admin@<tns_alias> @00_create_user.sql
-- Re-runnable: yes. An existing user is kept, the privileges are granted
--              again.
-- Note       : SEM_MATCH (RDF queries) needs Oracle Java on Autonomous AI
--              Database. Section 6 enables it with
--              DBMS_CLOUD_ADMIN.ENABLE_FEATURE (DEFINE enable_java).
--              The database must be restarted once afterwards.
--              Oracle Java cannot be disabled again.
-- Log        : logs/sql/00_create_user.log in the project folder,
--              overwritten on every run
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/00_create_user.log

-- Name of the demo user. Change it here if needed (also in 98 and 99).
DEFINE demo_user = DOAG2026

-- Y = enable Oracle Java if it is not installed yet (section 6).
-- Caution: cannot be undone and requires a restart.
DEFINE enable_java = Y

PROMPT
PROMPT === 00 Create demo user &demo_user ===

-- Run as ADMIN only
BEGIN
  IF SYS_CONTEXT('USERENV', 'SESSION_USER') <> 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'This script must run as ADMIN, not as '
                                    || SYS_CONTEXT('USERENV', 'SESSION_USER') || '.');
  END IF;
END;
/

-- Ask for the password without echoing it. Autonomous AI Database rules:
-- 12 to 30 characters, at least one upper-case letter, one lower-case letter
-- and one digit, no double quote, not the user name.
ACCEPT demo_pwd CHAR PROMPT 'Password for &demo_user: ' HIDE

--------------------------------------------------------------------------------
-- 1. User
--------------------------------------------------------------------------------
-- Tablespace DATA is predefined on Autonomous AI Database. The RDF network
-- tables are stored there as well (prerequisite for SEM_APIS.CREATE_RDF_NETWORK).
CREATE USER IF NOT EXISTS &demo_user
  IDENTIFIED BY "&demo_pwd"
  DEFAULT TABLESPACE data
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON data;

-- On a re-run: make sure the quota is set (the password stays unchanged)
ALTER USER &demo_user QUOTA UNLIMITED ON data;

UNDEFINE demo_pwd

--------------------------------------------------------------------------------
-- 2. Roles and system privileges
--------------------------------------------------------------------------------
-- DB_DEVELOPER_ROLE (23ai and later) contains, among others, CREATE SESSION,
-- TABLE, VIEW, SEQUENCE, PROCEDURE, TYPE, TRIGGER, PROPERTY GRAPH, MINING
-- MODEL, JOB, DOMAIN, MLE and the roles RESOURCE, CTXAPP (Oracle Text) and
-- SODA_APP (SODA, JSON collections). This covers:
--   JSON and duality views, Oracle Text, Vector Search (ONNX models via
--   CREATE MINING MODEL), SQL Property Graph and DBMS_SCHEDULER.
GRANT DB_DEVELOPER_ROLE TO &demo_user;

--------------------------------------------------------------------------------
-- 2a. RDF Graph (08_create_rdf_network.sql, 09a_load_knee_kg.sql, 09b_load_fma.sql)
--------------------------------------------------------------------------------
-- The demo user owns the RDF network RDF_NETWORK (on Autonomous AI Database
-- the only network, schema-private). According to the Oracle documentation
-- the network owner needs CONNECT, RESOURCE and CREATE VIEW plus quota on
-- the network's tablespace (DATA, see above).
GRANT CONNECT, RESOURCE TO &demo_user;
GRANT CREATE VIEW TO &demo_user;

-- SEM_APIS creates tables, views, sequences, triggers, procedures and types
-- in the owner's schema (network, graphs, inference, rulebase). Otherwise
-- these system privileges only come through roles; granted directly they
-- also apply in stored PL/SQL and in scheduler jobs.
GRANT CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER,
      CREATE PROCEDURE, CREATE TYPE TO &demo_user;

--------------------------------------------------------------------------------
-- 3. Additional privileges (one by one, so a missing privilege does not stop
--    everything)
--------------------------------------------------------------------------------
DECLARE
  TYPE t_stmts IS TABLE OF VARCHAR2(400);
  l_user  CONSTANT VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(UPPER('&demo_user'));
  l_stmts t_stmts := t_stmts(
    -- Oracle Text (06_create_text_index.sql). CTXAPP is already part of
    -- DB_DEVELOPER_ROLE and is sufficient for CREATE INDEX ... INDEXTYPE IS
    -- CTXSYS.CONTEXT and for CTX_DDL in SQLcl and anonymous blocks.
    -- Roles do not apply in stored PL/SQL and scheduler jobs, though;
    -- for those, the packages are granted directly as well.
    -- CTX_DDL is also needed by SEM_APIS.ADD_DATATYPE_INDEX for the text
    -- index on the RDF literals (09b_load_fma.sql, orardf:textContains).
    'GRANT CTXAPP TO ' || l_user,
    'GRANT EXECUTE ON CTXSYS.CTX_DDL TO '    || l_user,   -- preferences, stoplists, SYNC_INDEX, OPTIMIZE_INDEX, RDF text index
    'GRANT EXECUTE ON CTXSYS.CTX_QUERY TO '  || l_user,   -- hit counts, query helpers
    'GRANT EXECUTE ON CTXSYS.CTX_DOC TO '    || l_user,   -- markup and snippets of hits
    'GRANT EXECUTE ON CTXSYS.CTX_REPORT TO ' || l_user,   -- index reports
    'GRANT EXECUTE ON CTXSYS.CTX_OUTPUT TO ' || l_user,   -- logging during indexing
    -- AI Vector Search: embeddings and models in the database
    'GRANT EXECUTE ON SYS.DBMS_VECTOR TO '       || l_user,
    'GRANT EXECUTE ON SYS.DBMS_VECTOR_CHAIN TO ' || l_user,
    -- Object storage and credentials (e.g. loading the ONNX model)
    'GRANT EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD TO '    || l_user,
    -- Stage and import the ONNX file (05_create_embeddings.sql)
    'GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO '    || l_user,
    -- Select AI (optional part of the finale)
    'GRANT EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD_AI TO ' || l_user,
    -- Graph Studio and graph tools in Database Actions
    'GRANT GRAPH_DEVELOPER TO ' || l_user
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
-- 4. Routing with SDO_GCDR.ELOC_ROUTE (Autonomous AI Database only, ADMIN only)
--------------------------------------------------------------------------------
BEGIN
  SDO_GCDR.ELOC_GRANT_ACCESS(UPPER('&demo_user'));
  DBMS_OUTPUT.PUT_LINE('OK      SDO_GCDR.ELOC_GRANT_ACCESS(' || UPPER('&demo_user') || ')');
END;
/

--------------------------------------------------------------------------------
-- 5. Enable Database Actions (SQL Worksheet, Graph Studio, map view)
--------------------------------------------------------------------------------
BEGIN
  ORDS_ADMIN.ENABLE_SCHEMA(
    p_enabled             => TRUE,
    p_schema              => UPPER('&demo_user'),
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => LOWER('&demo_user'),
    p_auto_rest_auth      => TRUE);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('OK      ORDS_ADMIN.ENABLE_SCHEMA(' || UPPER('&demo_user') || ')');
END;
/

--------------------------------------------------------------------------------
-- 6. Enable Oracle Java (for SEM_MATCH in 09a, 09b and in the demo)
--    Source: "Use Oracle Java on Autonomous AI Database"
--    https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/autonomous-oracle-java.html
--    Steps:
--      a) DBMS_CLOUD_ADMIN.ENABLE_FEATURE(feature_name => 'JAVAVM') as ADMIN
--      b) Restart the database: OCI Console, Autonomous AI Database page,
--         menu "More actions" > "Restart", or OCI CLI:
--           oci db autonomous-database restart --autonomous-database-id <OCID>
--      c) After the restart the installation keeps running for a while.
--         It is complete when DBA_REGISTRY shows status VALID for JAVAVM:
--           SELECT status, version FROM dba_registry WHERE comp_id = 'JAVAVM';
--         VALID = complete, LOADING = still running, no row = not installed.
--         Additionally: SELECT dbms_java.get_jdk_version FROM dual;
--    Notes from the documentation:
--      - Oracle Java cannot be disabled once it is enabled.
--      - While Java is patched in the maintenance window, Java calls may
--        hang or fail with ORA-29548; they work again afterwards.
--------------------------------------------------------------------------------
DECLARE
  l_status  VARCHAR2(30);
  l_version VARCHAR2(30);
BEGIN
  SELECT MAX(status), MAX(version)
  INTO   l_status, l_version
  FROM   dba_registry
  WHERE  comp_id = 'JAVAVM';

  IF l_status = 'VALID' THEN
    DBMS_OUTPUT.PUT_LINE('OK      Oracle Java is installed (JAVAVM ' || l_version || ')');
  ELSIF l_status IS NOT NULL THEN
    DBMS_OUTPUT.PUT_LINE('OK      Oracle Java is being installed (status ' || l_status
                         || '). Check again later.');
  ELSIF UPPER('&enable_java') = 'Y' THEN
    DBMS_CLOUD_ADMIN.ENABLE_FEATURE(feature_name => 'JAVAVM');
    DBMS_OUTPUT.PUT_LINE('OK      DBMS_CLOUD_ADMIN.ENABLE_FEATURE(''JAVAVM'') requested');
    DBMS_OUTPUT.PUT_LINE('IMPORTANT Restart the database now (OCI Console: More actions > Restart).');
    DBMS_OUTPUT.PUT_LINE('          Then wait until DBA_REGISTRY shows status VALID for JAVAVM.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('WARNING Oracle Java is not installed (enable_java = N). '
                         || 'SEM_MATCH only works once it is enabled.');
  END IF;
END;
/

--------------------------------------------------------------------------------
-- 7. Checks
--------------------------------------------------------------------------------
PROMPT
PROMPT --- User
SELECT username, account_status, default_tablespace
FROM   dba_users
WHERE  username = UPPER('&demo_user');

PROMPT --- Roles
SELECT granted_role
FROM   dba_role_privs
WHERE  grantee = UPPER('&demo_user')
ORDER  BY granted_role;

PROMPT --- System privileges (granted directly)
SELECT privilege
FROM   dba_sys_privs
WHERE  grantee = UPPER('&demo_user')
ORDER  BY privilege;

PROMPT --- Object privileges
SELECT owner || '.' || table_name AS object_name, privilege
FROM   dba_tab_privs
WHERE  grantee = UPPER('&demo_user')
ORDER  BY 1, 2;

PROMPT --- Oracle Java (VALID = complete, LOADING = installation running, no row = not installed)
SELECT status, version
FROM   dba_registry
WHERE  comp_id = 'JAVAVM';

PROMPT
PROMPT Done. Continue with 01_run_all.sql as &demo_user.
PROMPT If Oracle Java was just requested: restart the database first.

SPOOL OFF
