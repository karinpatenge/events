--==============================================================================
--  02_02a_create_json_helpers.sql
--  Small JSON string/number helper package used by the BOM demo data generator.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Creating BOM_DEMO_JSON_PKG ===

CREATE OR REPLACE PACKAGE bom_demo_json_pkg AS
    FUNCTION q(p_text VARCHAR2) RETURN VARCHAR2;
    FUNCTION n(p_number NUMBER, p_scale PLS_INTEGER DEFAULT 3) RETURN VARCHAR2;
    FUNCTION b(p_condition BOOLEAN) RETURN VARCHAR2;
    FUNCTION iso_date(p_date DATE) RETURN VARCHAR2;
END bom_demo_json_pkg;
/

CREATE OR REPLACE PACKAGE BODY bom_demo_json_pkg AS
    FUNCTION q(p_text VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN '"' ||
               REPLACE(
                   REPLACE(
                       REPLACE(NVL(p_text, ''), CHR(92), CHR(92) || CHR(92)),
                       '"', CHR(92) || '"'),
                   CHR(10), CHR(92) || 'n') ||
               '"';
    END;

    FUNCTION n(p_number NUMBER, p_scale PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        IF p_number IS NULL THEN
            RETURN 'null';
        END IF;

        IF p_scale = 0 THEN
            RETURN TO_CHAR(ROUND(p_number), 'FM9999999999990', 'NLS_NUMERIC_CHARACTERS=.,');
        ELSIF p_scale = 1 THEN
            RETURN TO_CHAR(ROUND(p_number, 1), 'FM9999999999990D0', 'NLS_NUMERIC_CHARACTERS=.,');
        ELSIF p_scale = 2 THEN
            RETURN TO_CHAR(ROUND(p_number, 2), 'FM9999999999990D00', 'NLS_NUMERIC_CHARACTERS=.,');
        ELSIF p_scale = 4 THEN
            RETURN TO_CHAR(ROUND(p_number, 4), 'FM9999999999990D0000', 'NLS_NUMERIC_CHARACTERS=.,');
        ELSE
            RETURN TO_CHAR(ROUND(p_number, 3), 'FM9999999999990D000', 'NLS_NUMERIC_CHARACTERS=.,');
        END IF;
    END;

    FUNCTION b(p_condition BOOLEAN) RETURN VARCHAR2 IS
    BEGIN
        IF p_condition THEN
            RETURN 'true';
        ELSE
            RETURN 'false';
        END IF;
    END;

    FUNCTION iso_date(p_date DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN q(TO_CHAR(p_date, 'YYYY-MM-DD'));
    END;

END bom_demo_json_pkg;
/

SHOW ERRORS PACKAGE bom_demo_json_pkg
SHOW ERRORS PACKAGE BODY bom_demo_json_pkg

DECLARE
    v_error_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   v_error_count
    FROM   user_errors
    WHERE  name = 'BOM_DEMO_JSON_PKG'
    AND    type IN ('PACKAGE', 'PACKAGE BODY');

    IF v_error_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20000, 'BOM_DEMO_JSON_PKG compiled with errors. Run SHOW ERRORS PACKAGE BODY BOM_DEMO_JSON_PKG.');
    END IF;
END;
/

PROMPT === BOM_DEMO_JSON_PKG created ===
