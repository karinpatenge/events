--------------------------------------------------------------------------------
-- File       : 99_drop_user.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Removes the demo user from 00_create_user.sql completely.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as ADMIN, after 98_cleanup.sql has run as the demo
--              user (the RDF network must be removed through SEM_APIS
--              first, not just by DROP USER CASCADE)
--                sql admin@<tns_alias> @99_drop_user.sql
-- Caution    : Permanently drops the user and all remaining objects.
-- Log        : logs/sql/99_drop_user.log in the project folder,
--              overwritten on every run
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/99_drop_user.log

-- Must match the name in 00_create_user.sql
DEFINE demo_user = DOAG2026
-- RDF network: on Autonomous AI Database only the default network RDF_NETWORK
DEFINE network_name = RDF_NETWORK

PROMPT
PROMPT === 99 Drop user &demo_user ===

DECLARE
  l_cnt PLS_INTEGER;
BEGIN
  IF SYS_CONTEXT('USERENV', 'SESSION_USER') <> 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'This script must run as ADMIN.');
  END IF;

  -- RDF network still there? Then run 98_cleanup.sql first.
  SELECT COUNT(*) INTO l_cnt
  FROM   dba_tables
  WHERE  owner = UPPER('&demo_user')
  AND    table_name LIKE REPLACE('&network_name', '_', '\_') || '#%' ESCAPE '\';
  IF l_cnt > 0 THEN
    RAISE_APPLICATION_ERROR(-20003, 'The RDF network &network_name still exists. '
                                    || 'Run 98_cleanup.sql as &demo_user first.');
  END IF;

  -- Open sessions prevent DROP USER
  SELECT COUNT(*) INTO l_cnt FROM v$session WHERE username = UPPER('&demo_user');
  IF l_cnt > 0 THEN
    RAISE_APPLICATION_ERROR(-20004, l_cnt || ' session(s) of &demo_user are still open. '
                                    || 'Log them off first.');
  END IF;
END;
/

ACCEPT confirm CHAR PROMPT 'Permanently drop user &demo_user? Type the user name to confirm: '

BEGIN
  IF UPPER('&confirm') <> UPPER('&demo_user') THEN
    RAISE_APPLICATION_ERROR(-20002, 'Cancelled, nothing was dropped.');
  END IF;
END;
/

-- Disable Database Actions (ignore errors if it was never enabled)
BEGIN
  ORDS_ADMIN.ENABLE_SCHEMA(p_enabled => FALSE, p_schema => UPPER('&demo_user'));
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('WARNING ORDS_ADMIN.ENABLE_SCHEMA -> ' || SQLERRM);
END;
/

DROP USER IF EXISTS &demo_user CASCADE;

PROMPT
PROMPT Done. User &demo_user has been dropped.

SPOOL OFF
