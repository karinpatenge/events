--==============================================================================
--  02_04_load_components.sql
--  Load ~7,000 master components with native JSON specifications/compliance.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Loading BOM_COMPONENTS ===

DECLARE
    c_component_count CONSTANT PLS_INTEGER := 7000;

    TYPE t_cat_rec IS RECORD (
        category_id     NUMBER,
        category_code   VARCHAR2(20),
        category_name   VARCHAR2(100),
        powertrain_type VARCHAR2(20)
    );

    TYPE t_cat_tab IS TABLE OF t_cat_rec INDEX BY PLS_INTEGER;

    g_cat             t_cat_tab;
    g_cat_count       PLS_INTEGER := 0;

    v_cat_idx       PLS_INTEGER;
    v_component_id  NUMBER;
    v_category_id   NUMBER;
    v_part_number   VARCHAR2(50);
    v_component_nm  VARCHAR2(200);
    v_uom           VARCHAR2(20);
    v_ptype         VARCHAR2(20);
    v_status        VARCHAR2(20);
    v_cost          NUMBER;
    v_weight        NUMBER;
    v_specs         VARCHAR2(32767);
    v_compliance    VARCHAR2(32767);
BEGIN
    bom_demo_pick_pkg.seed_random(260126);
    bom_demo_bom_pkg.reset_caches;

    FOR r IN (
        SELECT category_id, category_code, category_name, powertrain_type
        FROM   bom_categories
        ORDER  BY category_id
    ) LOOP
        g_cat_count := g_cat_count + 1;
        g_cat(g_cat_count).category_id := r.category_id;
        g_cat(g_cat_count).category_code := r.category_code;
        g_cat(g_cat_count).category_name := r.category_name;
        g_cat(g_cat_count).powertrain_type := r.powertrain_type;
    END LOOP;

    IF g_cat_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'No BOM_CATEGORIES rows found. Run 02_03_load_categories.sql first.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('Loading ' || c_component_count || ' components...');

    FOR i IN 1 .. c_component_count LOOP
        v_cat_idx      := 1 + MOD(i - 1, g_cat_count);
        v_component_id := NULL;
        v_category_id  := g_cat(v_cat_idx).category_id;
        v_part_number  := 'BOM-' || g_cat(v_cat_idx).category_code || '-' || LPAD(i, 6, '0');
        v_uom          := CASE WHEN g_cat(v_cat_idx).category_code = 'FLUID' THEN 'L' ELSE 'EA' END;

        IF g_cat(v_cat_idx).category_code = 'VEH' THEN
            v_ptype := CASE MOD(i, 3) WHEN 0 THEN 'ICE' WHEN 1 THEN 'EV' ELSE 'HYBRID' END;
        ELSE
            v_ptype := g_cat(v_cat_idx).powertrain_type;
        END IF;

        v_component_nm := bom_demo_component_json_pkg.component_name_for(g_cat(v_cat_idx).category_code, v_ptype, i);
        v_cost         := bom_demo_component_json_pkg.base_cost(g_cat(v_cat_idx).category_code, i);
        v_weight       := bom_demo_component_json_pkg.base_weight(g_cat(v_cat_idx).category_code, i);
        v_status       := CASE
                            WHEN MOD(i, 179) = 0 THEN 'OBSOLETE'
                            WHEN MOD(i, 53)  = 0 THEN 'PHASE_OUT'
                            WHEN MOD(i, 37)  = 0 THEN 'PROTOTYPE'
                            ELSE 'ACTIVE'
                          END;
        v_specs        := bom_demo_component_json_pkg.make_component_specs(g_cat(v_cat_idx).category_code, v_ptype, i, v_weight, v_cost);
        v_compliance   := bom_demo_component_json_pkg.make_compliance(g_cat(v_cat_idx).category_code, v_ptype, i, v_weight);

        INSERT INTO bom_components (
            part_number, component_name, category_id, powertrain_type,
            unit_of_measure, standard_cost, weight_kg, lifecycle_status,
            created_date, specifications, compliance
        ) VALUES (
            v_part_number, v_component_nm, v_category_id, v_ptype,
            v_uom,
            v_cost, v_weight, v_status,
            DATE '2021-01-01' + MOD(i, 1200), JSON(v_specs), JSON(v_compliance)
        ) RETURNING component_id INTO v_component_id;

        IF MOD(i, 1000) = 0 THEN
            DBMS_OUTPUT.PUT_LINE('  components loaded: ' || i);
        END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('BOM_COMPONENTS loaded.');
END;
/
