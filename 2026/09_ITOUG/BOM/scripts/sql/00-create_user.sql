--==============================================================================
--  00-create_user.sql
--  Last update: 2026-08-31
--
--  Bill of Materials (BOM) demo user Oracle AI Database 26ai
--
--  Run this script while connected as:
--    * ADMIN in an Oracle Autonomous AI Database instance.
--    * SYS AS SYSDBA or SYSTEM in any other Oracle AI Database instance.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET DEFINE ON
SET VERIFY OFF

PROMPT
PROMPT === Creating BOMUSER ===
PROMPT Enter a password for BOMUSER. The value is not displayed.
ACCEPT bomuser_password CHAR PROMPT 'BOMUSER password: ' HIDE

PROMPT
PROMPT === Dropping existing BOMUSER (if any) ===
BEGIN
  EXECUTE IMMEDIATE 'DROP USER bomuser CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1918 THEN
      RAISE;
    END IF;
END;
/

PROMPT
PROMPT === Creating BOMUSER ===
SET ECHO OFF
CREATE USER bomuser
  IDENTIFIED BY "&bomuser_password"
  DEFAULT TABLESPACE data
  QUOTA UNLIMITED ON data;

PROMPT
PROMPT === Grant roles and permissions to BOMUSER ===
GRANT
  CREATE SESSION,
  CREATE TABLE,
  CREATE VIEW,
  CREATE SEQUENCE,
  CREATE PROCEDURE,
  CREATE PROPERTY GRAPH,
  CREATE ANY PROPERTY GRAPH,
  ALTER ANY PROPERTY GRAPH,
  DROP ANY PROPERTY GRAPH,
  READ ANY PROPERTY GRAPH
TO bomuser;

GRANT CONNECT TO bomuser;
GRANT CONSOLE_DEVELOPER TO bomuser;
GRANT GRAPH_DEVELOPER TO bomuser;
GRANT RESOURCE TO bomuser;
ALTER USER bomuser DEFAULT ROLE CONNECT,CONSOLE_DEVELOPER,GRAPH_DEVELOPER,RESOURCE;

PROMPT
PROMPT === Grant graph algorithm execution privileges to BOMUSER ===
GRANT EXECUTE ON DBMS_OGA TO bomuser;

PROMPT
PROMPT === REST-enable the BOMUSER schema to use Graph Studio ===
BEGIN
  ORDS_ADMIN.ENABLE_SCHEMA(
    p_enabled => TRUE,
    p_schema => 'BOMUSER',
    p_url_mapping_type => 'BASE_PATH',
    p_url_mapping_pattern => 'bom',
    p_auto_rest_auth=> FALSE
  );
  -- ENABLE DATA SHARING
  C##ADP$SERVICE.DBMS_SHARE.ENABLE_SCHEMA(
    SCHEMA_NAME => 'BOMUSER',
    ENABLED => TRUE
  );
  COMMIT;
END;
/

PROMPT
PROMPT === Enable Graph ===
ALTER USER bomuser GRANT CONNECT THROUGH GRAPH$PROXY_USER;

UNDEFINE bomuser_password
SET ECHO ON

PROMPT
PROMPT === BOMUSER created and enabled for SQL Property Graphs ===
