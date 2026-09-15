--==============================================================================
--  02_02-validate_packages.sql
--  Last update: 2026-08-28

--  Check and recompile BOM demo packages discovered from USER_OBJECTS.
--
--  Prerequisite:
--    * Run this script while connected as the BOMUSER application user.
--    * Create the BOM demo packages before running this script.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Checking BOM demo helper packages ===

DECLARE
  l_matching_object_count PLS_INTEGER;
  l_sql_statement VARCHAR2(4000);

  PROCEDURE compile_invalid_objects (
    p_object_type IN user_objects.object_type%TYPE
  ) IS
    l_object_cursor SYS_REFCURSOR;
    l_object_name user_objects.object_name%TYPE;
  BEGIN
    l_sql_statement := q'[
      SELECT
        object_name
      FROM user_objects
      WHERE object_name LIKE :package_name_prefix
        AND object_type = :object_type
        AND status <> 'VALID'
      ORDER BY
        object_name
    ]';

    OPEN l_object_cursor FOR l_sql_statement USING 'BOM%', p_object_type;
    LOOP
      FETCH l_object_cursor INTO l_object_name;
      EXIT WHEN l_object_cursor%NOTFOUND;

      IF p_object_type = 'PACKAGE' THEN
        l_sql_statement := 'ALTER PACKAGE ' ||
          DBMS_ASSERT.SIMPLE_SQL_NAME(l_object_name) || ' COMPILE';
      ELSE
        l_sql_statement := 'ALTER PACKAGE ' ||
          DBMS_ASSERT.SIMPLE_SQL_NAME(l_object_name) || ' COMPILE BODY';
      END IF;

      DBMS_OUTPUT.PUT_LINE(
        'Compiling ' || p_object_type || ' ' || l_object_name || '.'
      );
      EXECUTE IMMEDIATE l_sql_statement;
    END LOOP;

    CLOSE l_object_cursor;
  END compile_invalid_objects;
BEGIN
  l_sql_statement := q'[
    SELECT COUNT(*)
    FROM user_objects
    WHERE object_name LIKE :package_name_prefix
      AND object_type IN (
        'PACKAGE',
        'PACKAGE BODY'
      )
  ]';
  EXECUTE IMMEDIATE l_sql_statement
  INTO l_matching_object_count
  USING 'BOM%';

  IF l_matching_object_count = 0 THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'No package specifications or bodies beginning with BOM were found.'
    );
  END IF;

  compile_invalid_objects('PACKAGE');
  compile_invalid_objects('PACKAGE BODY');
END;
/

PROMPT
PROMPT === Helper package status ===
SELECT
  object_name,
  object_type,
  status
FROM user_objects
WHERE object_name LIKE 'BOM%'
  AND object_type IN (
    'PACKAGE',
    'PACKAGE BODY'
  )
ORDER BY
  object_name,
  object_type;

DECLARE
  l_invalid_count PLS_INTEGER;
  l_sql_statement VARCHAR2(4000);
BEGIN
  l_sql_statement := q'[
    SELECT COUNT(*)
    FROM user_objects
    WHERE object_name LIKE :package_name_prefix
      AND object_type IN (
        'PACKAGE',
        'PACKAGE BODY'
      )
      AND status <> 'VALID'
  ]';
  EXECUTE IMMEDIATE l_sql_statement
  INTO l_invalid_count
  USING 'BOM%';

  IF l_invalid_count > 0 THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'BOM package validation failed. Invalid objects: ' ||
      l_invalid_count || '.'
    );
  END IF;
END;
/

PROMPT
PROMPT === BOM demo helper packages are valid ===
