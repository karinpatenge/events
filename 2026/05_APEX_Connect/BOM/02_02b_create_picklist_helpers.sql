--==============================================================================
--  02_02b_create_picklist_helpers.sql
--  Deterministic picklist/value-selection helpers for realistic demo data.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Creating BOM_DEMO_PICK_PKG ===

CREATE OR REPLACE PACKAGE bom_demo_pick_pkg AS
    PROCEDURE seed_random(p_seed PLS_INTEGER DEFAULT 260126);

    FUNCTION pick_powertrain(p_seed PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION pick_region(p_seed PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION pick_market(p_seed PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION pick_trim(p_seed PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION pick_model(p_seed PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION pick_plant(p_seed PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION pick_engineer(p_seed PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION pick_supplier(p_seed PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION pick_material(p_seed PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION short_code(p_text VARCHAR2) RETURN VARCHAR2;
END bom_demo_pick_pkg;
/

CREATE OR REPLACE PACKAGE BODY bom_demo_pick_pkg AS
    PROCEDURE seed_random(p_seed PLS_INTEGER) IS
    BEGIN
        DBMS_RANDOM.SEED(p_seed);
    END;

    FUNCTION pick_powertrain(p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_seed, 10)
            WHEN 0 THEN RETURN 'EV';
            WHEN 1 THEN RETURN 'EV';
            WHEN 2 THEN RETURN 'EV';
            WHEN 3 THEN RETURN 'EV';
            WHEN 4 THEN RETURN 'ICE';
            WHEN 5 THEN RETURN 'ICE';
            WHEN 6 THEN RETURN 'ICE';
            ELSE RETURN 'HYBRID';
        END CASE;
    END;

    FUNCTION pick_region(p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_seed, 8)
            WHEN 0 THEN RETURN 'EU';
            WHEN 1 THEN RETURN 'NA';
            WHEN 2 THEN RETURN 'CN';
            WHEN 3 THEN RETURN 'JP';
            WHEN 4 THEN RETURN 'KR';
            WHEN 5 THEN RETURN 'IN';
            WHEN 6 THEN RETURN 'LATAM';
            ELSE RETURN 'MEA';
        END CASE;
    END;

    FUNCTION pick_market(p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_seed, 8)
            WHEN 0 THEN RETURN 'Retail Premium';
            WHEN 1 THEN RETURN 'Retail Core';
            WHEN 2 THEN RETURN 'Fleet';
            WHEN 3 THEN RETURN 'Taxi / Ride Hail';
            WHEN 4 THEN RETURN 'Sport Package';
            WHEN 5 THEN RETURN 'Cold Weather';
            WHEN 6 THEN RETURN 'Warm Climate';
            ELSE RETURN 'Police / Special Service';
        END CASE;
    END;

    FUNCTION pick_trim(p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_seed, 7)
            WHEN 0 THEN RETURN 'Base';
            WHEN 1 THEN RETURN 'Comfort';
            WHEN 2 THEN RETURN 'Sport';
            WHEN 3 THEN RETURN 'Premium';
            WHEN 4 THEN RETURN 'Luxury';
            WHEN 5 THEN RETURN 'Fleet';
            ELSE RETURN 'Performance';
        END CASE;
    END;

    FUNCTION pick_model(p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_seed, 12)
            WHEN 0 THEN RETURN 'Aster Sedan';
            WHEN 1 THEN RETURN 'Orion SUV';
            WHEN 2 THEN RETURN 'Nova Hatchback';
            WHEN 3 THEN RETURN 'Vela Crossover';
            WHEN 4 THEN RETURN 'Solara Coupe';
            WHEN 5 THEN RETURN 'Terra Wagon';
            WHEN 6 THEN RETURN 'Lynx Compact';
            WHEN 7 THEN RETURN 'Atlas MPV';
            WHEN 8 THEN RETURN 'Pulse Urban';
            WHEN 9 THEN RETURN 'Ridge Adventure';
            WHEN 10 THEN RETURN 'Meridian Executive';
            ELSE RETURN 'Comet Delivery Van';
        END CASE;
    END;

    FUNCTION pick_plant(p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_seed, 10)
            WHEN 0 THEN RETURN 'DE-LPZ';
            WHEN 1 THEN RETURN 'US-TX1';
            WHEN 2 THEN RETURN 'US-MI2';
            WHEN 3 THEN RETURN 'CN-SH1';
            WHEN 4 THEN RETURN 'JP-AIC';
            WHEN 5 THEN RETURN 'KR-ULS';
            WHEN 6 THEN RETURN 'IN-PUN';
            WHEN 7 THEN RETURN 'MX-GTO';
            WHEN 8 THEN RETURN 'BR-PRN';
            ELSE RETURN 'UK-MID';
        END CASE;
    END;

    FUNCTION pick_engineer(p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_seed, 12)
            WHEN 0 THEN RETURN 'Maya Fischer';
            WHEN 1 THEN RETURN 'Liam Chen';
            WHEN 2 THEN RETURN 'Sophia Wagner';
            WHEN 3 THEN RETURN 'Noah Patel';
            WHEN 4 THEN RETURN 'Emma Johansson';
            WHEN 5 THEN RETURN 'Lucas Martin';
            WHEN 6 THEN RETURN 'Ava Rossi';
            WHEN 7 THEN RETURN 'Ethan Miller';
            WHEN 8 THEN RETURN 'Isabella Novak';
            WHEN 9 THEN RETURN 'Oliver Smith';
            WHEN 10 THEN RETURN 'Amelia Garcia';
            ELSE RETURN 'Mateo Silva';
        END CASE;
    END;

    FUNCTION pick_supplier(p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_seed, 12)
            WHEN 0 THEN RETURN 'ContiMotion Systems';
            WHEN 1 THEN RETURN 'Bosch Mobility';
            WHEN 2 THEN RETURN 'Aisin Driveline';
            WHEN 3 THEN RETURN 'Magna Structures';
            WHEN 4 THEN RETURN 'ZF Chassis Tech';
            WHEN 5 THEN RETURN 'Valeo Thermal';
            WHEN 6 THEN RETURN 'Denso Electronics';
            WHEN 7 THEN RETURN 'LG Energy Mobility';
            WHEN 8 THEN RETURN 'Samsung SDI Auto';
            WHEN 9 THEN RETURN 'Forvia Interior';
            WHEN 10 THEN RETURN 'Lear Electrical';
            ELSE RETURN 'Aptiv Signal ' || CHR(38) || ' Power';
        END CASE;
    END;

    FUNCTION pick_material(p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE MOD(p_seed, 10)
            WHEN 0 THEN RETURN 'Aluminum 6061-T6';
            WHEN 1 THEN RETURN 'High-strength low-alloy steel';
            WHEN 2 THEN RETURN 'Glass-filled nylon PA66-GF30';
            WHEN 3 THEN RETURN 'EPDM rubber';
            WHEN 4 THEN RETURN 'Copper alloy C110';
            WHEN 5 THEN RETURN 'Stainless steel 304';
            WHEN 6 THEN RETURN 'Polypropylene T20';
            WHEN 7 THEN RETURN 'Magnesium alloy AZ91';
            WHEN 8 THEN RETURN 'Carbon fiber reinforced polymer';
            ELSE RETURN 'Automotive grade silicon';
        END CASE;
    END;

    FUNCTION short_code(p_text VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN SUBSTR(REPLACE(REPLACE(REPLACE(UPPER(p_text), ' ', ''), '/', ''), '-', ''), 1, 6);
    END;

END bom_demo_pick_pkg;
/

SHOW ERRORS PACKAGE bom_demo_pick_pkg
SHOW ERRORS PACKAGE BODY bom_demo_pick_pkg

DECLARE
    v_error_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   v_error_count
    FROM   user_errors
    WHERE  name = 'BOM_DEMO_PICK_PKG'
    AND    type IN ('PACKAGE', 'PACKAGE BODY');

    IF v_error_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20000, 'BOM_DEMO_PICK_PKG compiled with errors. Run SHOW ERRORS PACKAGE BODY BOM_DEMO_PICK_PKG.');
    END IF;
END;
/

PROMPT === BOM_DEMO_PICK_PKG created ===
