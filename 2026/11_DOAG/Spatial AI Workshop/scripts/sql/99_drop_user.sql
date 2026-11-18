--------------------------------------------------------------------------------
-- File       : 99_drop_user.sql
-- Project    : DOAG 2026 - "Spatial AI in Python: Unlocking Machine Learning
--              for Geospatial Intelligence" (workshop)
-- Purpose    : Removes a workshop user from 00_create_user.sql completely.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as ADMIN, in folder scripts/sql, with the user name
--              as the first argument (environment variable WORKSHOP_USER):
--                sql admin@<tns_alias> @99_drop_user.sql %WORKSHOP_USER%
--              The script then asks for the user name and shows the first
--              argument as default: press Enter to accept it. Without an
--              argument, type the name.
-- Caution    : Permanently drops the user and all objects in its schema.
--              Export OML notebooks and Spatial Studio projects you want to
--              keep before you run it.
-- Log        : log/sql/99_drop_user.log in the project folder,
--              overwritten on every run
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
PROMPT Name of the workshop database user to DROP (created with 00_create_user.sql):
ACCEPT workshop_user CHAR DEFAULT '&1' PROMPT 'Database user name&user_hint: '

SPOOL ../../log/sql/99_drop_user.log REPLACE

PROMPT
PROMPT === 99 Drop workshop user &workshop_user ===

DECLARE
  l_cnt PLS_INTEGER;
BEGIN
  IF SYS_CONTEXT('USERENV', 'SESSION_USER') <> 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'This script must run as ADMIN.');
  END IF;

  IF NOT REGEXP_LIKE('&workshop_user', '^[A-Za-z][A-Za-z0-9_]{0,127}$')
     OR UPPER('&workshop_user') IN ('ADMIN', 'SYS', 'SYSTEM', 'PUBLIC', 'OML$PROXY',
                                    'SPATIAL$PROXY_USER') THEN
    RAISE_APPLICATION_ERROR(-20003, 'Invalid or reserved user name "&workshop_user".');
  END IF;

  -- Open sessions prevent DROP USER
  SELECT COUNT(*) INTO l_cnt FROM v$session WHERE username = UPPER('&workshop_user');
  IF l_cnt > 0 THEN
    RAISE_APPLICATION_ERROR(-20004, l_cnt || ' session(s) of &workshop_user are still open. '
                                    || 'Log them off first.');
  END IF;
END;
/

ACCEPT confirm CHAR PROMPT 'Permanently drop user &workshop_user? Type the user name to confirm: '

BEGIN
  IF UPPER('&confirm') <> UPPER('&workshop_user') THEN
    RAISE_APPLICATION_ERROR(-20002, 'Cancelled, nothing was dropped.');
  END IF;
END;
/

-- Disable Database Actions (ignore errors if it was never enabled)
BEGIN
  ORDS_ADMIN.ENABLE_SCHEMA(p_enabled => FALSE, p_schema => UPPER('&workshop_user'));
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('WARNING ORDS_ADMIN.ENABLE_SCHEMA -> ' || SQLERRM);
END;
/

DROP USER IF EXISTS &workshop_user CASCADE;

PROMPT
PROMPT Done. User &workshop_user has been dropped.

SPOOL OFF
