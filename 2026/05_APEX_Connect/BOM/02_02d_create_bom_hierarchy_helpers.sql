--==============================================================================
--  02_02d_create_bom_hierarchy_helpers.sql
--  BOM hierarchy helper routines, component/revision/variant lookup, and add_item.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Creating BOM_DEMO_BOM_PKG ===

CREATE OR REPLACE PACKAGE bom_demo_bom_pkg AS
    PROCEDURE reset_caches;

    FUNCTION make_header_metadata(
        p_bom_code VARCHAR2,
        p_model    VARCHAR2,
        p_ptype    VARCHAR2,
        p_year     NUMBER,
        p_trim     VARCHAR2,
        p_plant    VARCHAR2,
        p_seq      PLS_INTEGER
    ) RETURN VARCHAR2;

    FUNCTION make_item_attrs(
        p_cat_code VARCHAR2,
        p_level    PLS_INTEGER,
        p_seq      PLS_INTEGER,
        p_qty      NUMBER
    ) RETURN VARCHAR2;

    FUNCTION choose_component(
        p_category_code VARCHAR2,
        p_powertrain    VARCHAR2,
        p_seed          PLS_INTEGER
    ) RETURN NUMBER;

    FUNCTION latest_revision_id(p_component_id NUMBER) RETURN NUMBER;
    FUNCTION first_variant_id(p_component_id NUMBER) RETURN NUMBER;
    FUNCTION major_system_cat(p_ptype VARCHAR2, p_system_no PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION subsystem_cat(p_ptype VARCHAR2, p_system_no PLS_INTEGER, p_sub_no PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION leaf_cat(p_ptype VARCHAR2, p_system_no PLS_INTEGER, p_sub_no PLS_INTEGER) RETURN VARCHAR2;
    FUNCTION ref_des(p_cat_code VARCHAR2, p_seed PLS_INTEGER) RETURN VARCHAR2;

    PROCEDURE add_item(
        p_bom_id        NUMBER,
        p_parent_id     NUMBER,
        p_cat_code      VARCHAR2,
        p_powertrain    VARCHAR2,
        p_level         PLS_INTEGER,
        p_sequence      PLS_INTEGER,
        p_find_number   VARCHAR2,
        p_quantity      NUMBER,
        p_seed          PLS_INTEGER,
        p_item_id       OUT NUMBER
    );
END bom_demo_bom_pkg;
/

CREATE OR REPLACE PACKAGE BODY bom_demo_bom_pkg AS
    TYPE t_num_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    g_latest_revision t_num_tab;
    g_first_variant   t_num_tab;

    PROCEDURE reset_caches IS
    BEGIN
        g_latest_revision.DELETE;
        g_first_variant.DELETE;
    END;

    FUNCTION make_header_metadata(
        p_bom_code VARCHAR2,
        p_model    VARCHAR2,
        p_ptype    VARCHAR2,
        p_year     NUMBER,
        p_trim     VARCHAR2,
        p_plant    VARCHAR2,
        p_seq      PLS_INTEGER
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN '{' ||
               '"schema":"bom.header.metadata.v1",' ||
               '"vehicleProgram":{' ||
                   '"programCode":' || bom_demo_json_pkg.q('PGM-' || SUBSTR(p_bom_code, 5)) || ',' ||
                   '"model":' || bom_demo_json_pkg.q(p_model) || ',' ||
                   '"modelYear":' || bom_demo_json_pkg.n(p_year, 0) || ',' ||
                   '"trim":' || bom_demo_json_pkg.q(p_trim) || ',' ||
                   '"powertrain":' || bom_demo_json_pkg.q(p_ptype) ||
               '},' ||
               '"plant":{' ||
                   '"plantCode":' || bom_demo_json_pkg.q(p_plant) || ',' ||
                   '"line":' || bom_demo_json_pkg.q('LINE-' || TO_CHAR(1 + MOD(p_seq, 4))) || ',' ||
                   '"taktSeconds":' || bom_demo_json_pkg.n(58 + MOD(p_seq, 8) * 6, 0) ||
               '},' ||
               '"commercialTargets":{' ||
                   '"annualVolume":' || bom_demo_json_pkg.n(12000 + MOD(p_seq, 40) * 2500, 0) || ',' ||
                   '"targetMarkets":[' || bom_demo_json_pkg.q(bom_demo_pick_pkg.pick_region(p_seq)) || ',' || bom_demo_json_pkg.q(bom_demo_pick_pkg.pick_region(p_seq + 2)) || ',' || bom_demo_json_pkg.q(bom_demo_pick_pkg.pick_region(p_seq + 5)) || '],' ||
                   '"targetContributionMarginPct":' || bom_demo_json_pkg.n(8 + MOD(p_seq, 12) * 0.8, 1) ||
               '},' ||
               '"engineeringTargets":{' ||
                   '"rangeKm":' || bom_demo_json_pkg.n(CASE WHEN p_ptype = 'EV' THEN 380 + MOD(p_seq, 8) * 45 WHEN p_ptype = 'HYBRID' THEN 700 + MOD(p_seq, 6) * 35 ELSE 650 + MOD(p_seq, 5) * 30 END, 0) || ',' ||
                   '"co2GPerKm":' || bom_demo_json_pkg.n(CASE WHEN p_ptype = 'EV' THEN 0 WHEN p_ptype = 'HYBRID' THEN 45 + MOD(p_seq, 6) * 7 ELSE 95 + MOD(p_seq, 10) * 8 END, 0) || ',' ||
                   '"safetyRatingTarget":"5-star NCAP",' ||
                   '"softwareDefinedVehicle":' || bom_demo_json_pkg.b(MOD(p_seq, 3) <> 0) ||
               '}' ||
               '}';
    END;

    FUNCTION make_item_attrs(
        p_cat_code VARCHAR2,
        p_level    PLS_INTEGER,
        p_seq      PLS_INTEGER,
        p_qty      NUMBER
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN '{' ||
               '"schema":"bom.item.attributes.v1",' ||
               '"installation":{' ||
                   '"station":' || bom_demo_json_pkg.q('ST-' || LPAD(10 + MOD(p_seq, 70), 3, '0')) || ',' ||
                   '"method":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 7) WHEN 0 THEN 'Robotic fastening' WHEN 1 THEN 'Manual fitment' WHEN 2 THEN 'Adhesive bead' WHEN 3 THEN 'Torque controlled' WHEN 4 THEN 'Clip-in' WHEN 5 THEN 'Press fit' ELSE 'End-of-line calibration' END) || ',' ||
                   '"torqueNm":' || bom_demo_json_pkg.n(CASE WHEN p_cat_code = 'FASTENER' THEN 4 + MOD(p_seq, 12) * 6 WHEN p_level >= 4 THEN 8 + MOD(p_seq, 10) * 3 ELSE 0 END, 1) || ',' ||
                   '"quantityBasis":' || bom_demo_json_pkg.q(CASE WHEN p_qty = 1 THEN 'per vehicle' ELSE 'per assembly' END) ||
               '},' ||
               '"quality":{' ||
                   '"criticality":' || bom_demo_json_pkg.q(CASE WHEN p_cat_code IN ('BRAKE', 'STEER', 'SAFETY', 'BATTERY', 'PE', 'ADAS') THEN 'Critical' WHEN p_level <= 2 THEN 'Major' ELSE 'Standard' END) || ',' ||
                   '"traceability":' || bom_demo_json_pkg.q(CASE WHEN p_cat_code IN ('BATTERY', 'PE', 'SAFETY', 'ADAS') THEN 'Serial' WHEN p_cat_code IN ('FASTENER', 'FLUID') THEN 'Batch' ELSE 'Lot' END) || ',' ||
                   '"pokaYokeRequired":' || bom_demo_json_pkg.b(MOD(p_seq, 4) = 0 OR p_cat_code IN ('SAFETY', 'BRAKE')) ||
               '},' ||
               '"service":{' ||
                   '"serviceable":' || bom_demo_json_pkg.b(p_cat_code NOT IN ('FASTENER', 'FLUID')) || ',' ||
                   '"removalTimeMinutes":' || bom_demo_json_pkg.n(5 + MOD(p_seq, 15) * 4, 0) || ',' ||
                   '"specialTool":' || bom_demo_json_pkg.q(CASE WHEN p_cat_code IN ('BATTERY', 'PE', 'EDRIVE') THEN 'HV insulated tool set' WHEN p_cat_code IN ('BRAKE', 'STEER') THEN 'diagnostic bleed/calibration tool' ELSE 'standard workshop tools' END) ||
               '}' ||
               '}';
    END;


    FUNCTION choose_component(
        p_category_code VARCHAR2,
        p_powertrain    VARCHAR2,
        p_seed          PLS_INTEGER
    ) RETURN NUMBER IS
        v_count  PLS_INTEGER;
        v_target PLS_INTEGER;
        v_id     NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO   v_count
        FROM   bom_components c
               JOIN bom_categories ca ON ca.category_id = c.category_id
        WHERE  ca.category_code = p_category_code
        AND    c.powertrain_type = p_powertrain;

        IF v_count > 0 THEN
            v_target := 1 + MOD(ABS(p_seed), v_count);
            SELECT component_id
            INTO   v_id
            FROM  (
                SELECT c.component_id,
                       ROW_NUMBER() OVER (ORDER BY c.component_id) rn
                FROM   bom_components c
                       JOIN bom_categories ca ON ca.category_id = c.category_id
                WHERE  ca.category_code = p_category_code
                AND    c.powertrain_type = p_powertrain
            )
            WHERE rn = v_target;
            RETURN v_id;
        END IF;

        SELECT COUNT(*)
        INTO   v_count
        FROM   bom_components c
               JOIN bom_categories ca ON ca.category_id = c.category_id
        WHERE  ca.category_code = p_category_code
        AND    c.powertrain_type = 'COMMON';

        IF v_count > 0 THEN
            v_target := 1 + MOD(ABS(p_seed), v_count);
            SELECT component_id
            INTO   v_id
            FROM  (
                SELECT c.component_id,
                       ROW_NUMBER() OVER (ORDER BY c.component_id) rn
                FROM   bom_components c
                       JOIN bom_categories ca ON ca.category_id = c.category_id
                WHERE  ca.category_code = p_category_code
                AND    c.powertrain_type = 'COMMON'
            )
            WHERE rn = v_target;
            RETURN v_id;
        END IF;

        SELECT COUNT(*)
        INTO   v_count
        FROM   bom_components c
               JOIN bom_categories ca ON ca.category_id = c.category_id
        WHERE  ca.category_code = p_category_code;

        IF v_count > 0 THEN
            v_target := 1 + MOD(ABS(p_seed), v_count);
            SELECT component_id
            INTO   v_id
            FROM  (
                SELECT c.component_id,
                       ROW_NUMBER() OVER (ORDER BY c.component_id) rn
                FROM   bom_components c
                       JOIN bom_categories ca ON ca.category_id = c.category_id
                WHERE  ca.category_code = p_category_code
            )
            WHERE rn = v_target;
            RETURN v_id;
        END IF;

        SELECT component_id INTO v_id
        FROM   (SELECT component_id FROM bom_components ORDER BY component_id)
        WHERE  ROWNUM = 1;

        RETURN v_id;
    END;

    FUNCTION latest_revision_id(p_component_id NUMBER) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        IF g_latest_revision.EXISTS(p_component_id) THEN
            RETURN g_latest_revision(p_component_id);
        END IF;

        SELECT revision_id
        INTO   v_id
        FROM  (
            SELECT revision_id
            FROM   bom_component_revisions
            WHERE  component_id = p_component_id
            ORDER  BY revision_code DESC
        )
        WHERE ROWNUM = 1;

        g_latest_revision(p_component_id) := v_id;
        RETURN v_id;
    END;

    FUNCTION first_variant_id(p_component_id NUMBER) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        IF g_first_variant.EXISTS(p_component_id) THEN
            RETURN g_first_variant(p_component_id);
        END IF;

        SELECT variant_id
        INTO   v_id
        FROM  (
            SELECT variant_id
            FROM   bom_component_variants
            WHERE  component_id = p_component_id
            ORDER  BY variant_id
        )
        WHERE ROWNUM = 1;

        g_first_variant(p_component_id) := v_id;
        RETURN v_id;
    END;

    FUNCTION major_system_cat(p_ptype VARCHAR2, p_system_no PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        CASE p_system_no
            WHEN 1 THEN
                IF p_ptype = 'EV' THEN RETURN 'BATTERY';
                ELSIF p_ptype = 'HYBRID' THEN RETURN 'HYBRIDCTRL';
                ELSE RETURN 'ENGINE';
                END IF;
            WHEN 2 THEN RETURN 'BODY';
            WHEN 3 THEN RETURN 'CHASSIS';
            WHEN 4 THEN RETURN 'ELECTRICAL';
            WHEN 5 THEN RETURN 'INTERIOR';
            WHEN 6 THEN RETURN 'EXTERIOR';
            WHEN 7 THEN RETURN 'SAFETY';
            ELSE RETURN CASE WHEN p_ptype = 'ICE' THEN 'EXHAUST' ELSE 'THERMAL' END;
        END CASE;
    END;

    FUNCTION subsystem_cat(p_ptype VARCHAR2, p_system_no PLS_INTEGER, p_sub_no PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        IF p_system_no = 1 THEN
            IF p_ptype = 'EV' THEN
                RETURN CASE p_sub_no WHEN 1 THEN 'EDRIVE' ELSE 'PE' END;
            ELSIF p_ptype = 'HYBRID' THEN
                RETURN CASE p_sub_no WHEN 1 THEN 'ENGINE' ELSE 'BATTERY' END;
            ELSE
                RETURN CASE p_sub_no WHEN 1 THEN 'FUEL' ELSE 'TRANS' END;
            END IF;
        ELSIF p_system_no = 2 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'BODY' ELSE 'CHASSIS' END;
        ELSIF p_system_no = 3 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'SUSP' ELSE 'BRAKE' END;
        ELSIF p_system_no = 4 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'HARNESS' ELSE 'INFOTAIN' END;
        ELSIF p_system_no = 5 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'HVAC' ELSE 'INTERIOR' END;
        ELSIF p_system_no = 6 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'EXTERIOR' ELSE 'ADAS' END;
        ELSIF p_system_no = 7 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'SENSOR' ELSE 'SAFETY' END;
        ELSE
            RETURN CASE p_sub_no WHEN 1 THEN 'THERMAL' ELSE 'FLUID' END;
        END IF;
    END;

    FUNCTION leaf_cat(p_ptype VARCHAR2, p_system_no PLS_INTEGER, p_sub_no PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        IF p_system_no = 1 THEN
            IF p_ptype = 'EV' THEN
                RETURN CASE p_sub_no WHEN 1 THEN 'CHARGING' ELSE 'HARNESS' END;
            ELSIF p_ptype = 'HYBRID' THEN
                RETURN CASE p_sub_no WHEN 1 THEN 'EXHAUST' ELSE 'PE' END;
            ELSE
                RETURN CASE p_sub_no WHEN 1 THEN 'SENSOR' ELSE 'FLUID' END;
            END IF;
        ELSIF p_system_no = 2 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'FASTENER' ELSE 'EXTERIOR' END;
        ELSIF p_system_no = 3 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'STEER' ELSE 'FASTENER' END;
        ELSIF p_system_no = 4 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'ELECTRICAL' ELSE 'SENSOR' END;
        ELSIF p_system_no = 5 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'THERMAL' ELSE 'FASTENER' END;
        ELSIF p_system_no = 6 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'SENSOR' ELSE 'HARNESS' END;
        ELSIF p_system_no = 7 THEN
            RETURN CASE p_sub_no WHEN 1 THEN 'ELECTRICAL' ELSE 'FASTENER' END;
        ELSE
            RETURN CASE p_sub_no WHEN 1 THEN 'SENSOR' ELSE 'FASTENER' END;
        END IF;
    END;

    FUNCTION ref_des(p_cat_code VARCHAR2, p_seed PLS_INTEGER) RETURN VARCHAR2 IS
    BEGIN
        IF p_cat_code IN ('ELECTRICAL', 'HARNESS', 'SENSOR', 'ADAS', 'PE', 'INFOTAIN', 'BATTERY', 'EDRIVE') THEN
            RETURN 'J' || TO_CHAR(100 + MOD(p_seed, 700)) || '/P' || TO_CHAR(1 + MOD(p_seed, 80));
        ELSIF p_cat_code IN ('FASTENER') THEN
            RETURN 'F' || TO_CHAR(1000 + MOD(p_seed, 9000));
        ELSE
            RETURN NULL;
        END IF;
    END;

    PROCEDURE add_item(
        p_bom_id        NUMBER,
        p_parent_id     NUMBER,
        p_cat_code      VARCHAR2,
        p_powertrain    VARCHAR2,
        p_level         PLS_INTEGER,
        p_sequence      PLS_INTEGER,
        p_find_number   VARCHAR2,
        p_quantity      NUMBER,
        p_seed          PLS_INTEGER,
        p_item_id       OUT NUMBER
    ) IS
        v_component_id NUMBER;
        v_revision_id  NUMBER;
        v_variant_id   NUMBER;
        v_attrs        VARCHAR2(32767);
        v_ref_des      VARCHAR2(200);
    BEGIN
        v_component_id := choose_component(p_cat_code, p_powertrain, p_seed);
        v_revision_id  := latest_revision_id(v_component_id);

        IF MOD(p_seed, 4) = 0 OR p_cat_code IN ('INTERIOR', 'EXTERIOR', 'INFOTAIN', 'HARNESS', 'CHARGING') THEN
            v_variant_id := first_variant_id(v_component_id);
        ELSE
            v_variant_id := NULL;
        END IF;

        v_attrs   := make_item_attrs(p_cat_code, p_level, p_seed, p_quantity);
        v_ref_des := ref_des(p_cat_code, p_seed);

        INSERT INTO bom_items (
            bom_id, parent_item_id, component_id, revision_id, variant_id,
            level_num, sequence_num, find_number, quantity,
            reference_designator, item_attributes
        ) VALUES (
            p_bom_id, p_parent_id, v_component_id, v_revision_id, v_variant_id,
            p_level, p_sequence, p_find_number, p_quantity,
            v_ref_des, JSON(v_attrs)
        ) RETURNING bom_item_id INTO p_item_id;
    END;
END bom_demo_bom_pkg;
/

SHOW ERRORS PACKAGE bom_demo_bom_pkg
SHOW ERRORS PACKAGE BODY bom_demo_bom_pkg

DECLARE
    v_error_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   v_error_count
    FROM   user_errors
    WHERE  name = 'BOM_DEMO_BOM_PKG'
    AND    type IN ('PACKAGE', 'PACKAGE BODY');

    IF v_error_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20000, 'BOM_DEMO_BOM_PKG compiled with errors. Run SHOW ERRORS PACKAGE BODY BOM_DEMO_BOM_PKG.');
    END IF;
END;
/

PROMPT === BOM_DEMO_BOM_PKG created ===
