--==============================================================================
--  02_06_load_component_variants.sql
--  Load ~15,000 market/region/trim component variants.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Loading BOM_COMPONENT_VARIANTS ===

DECLARE
    c_component_count CONSTANT PLS_INTEGER := 7000;
    c_variant_count   CONSTANT PLS_INTEGER := 15000;

    v_variant_id       NUMBER;
    v_region           VARCHAR2(10);
    v_market           VARCHAR2(50);
    v_variant_attrs    VARCHAR2(32767);
    v_variant_code     VARCHAR2(50);
    v_variant_name     VARCHAR2(200);
    v_extra_variants   PLS_INTEGER;
    v_variant_rows     PLS_INTEGER := 0;
BEGIN
    bom_demo_bom_pkg.reset_caches;
    DBMS_OUTPUT.PUT_LINE('Loading ' || c_variant_count || ' component variants...');

    v_extra_variants := GREATEST(0, c_variant_count - (2 * c_component_count));

    FOR c IN (
        SELECT c.component_id,
               c.part_number,
               c.component_name,
               c.powertrain_type,
               ca.category_code,
               ROW_NUMBER() OVER (ORDER BY c.component_id) rn
        FROM   bom_components c
               JOIN bom_categories ca ON ca.category_id = c.category_id
        ORDER  BY c.component_id
    ) LOOP
        FOR v IN 1 .. (2 + CASE WHEN c.rn <= v_extra_variants THEN 1 ELSE 0 END) LOOP
            v_region        := bom_demo_pick_pkg.pick_region(c.rn + v);
            v_market        := bom_demo_pick_pkg.pick_market(c.rn + v * 3);
            v_variant_code  := SUBSTR(c.part_number || '-' || bom_demo_pick_pkg.short_code(v_region) || '-' || bom_demo_pick_pkg.short_code(bom_demo_pick_pkg.pick_trim(c.rn + v)), 1, 50);
            v_variant_name  := SUBSTR(c.component_name || ' / ' || v_region || ' ' || bom_demo_pick_pkg.pick_trim(c.rn + v), 1, 200);
            v_variant_attrs := bom_demo_component_json_pkg.make_variant_attrs(c.category_code, c.powertrain_type, c.rn, v, v_region, v_market);

            INSERT INTO bom_component_variants (
                component_id, variant_code, variant_name, region_code, market_segment,
                cost_adjustment, variant_status, variant_attributes
            ) VALUES (
                c.component_id, v_variant_code, v_variant_name, v_region, v_market,
                ROUND((MOD(c.rn + v, 17) - 8) * 1.75, 4),
                CASE WHEN MOD(c.rn + v, 97) = 0 THEN 'OBSOLETE'
                     WHEN MOD(c.rn + v, 29) = 0 THEN 'PILOT'
                     ELSE 'ACTIVE'
                END,
                JSON(v_variant_attrs)
            ) RETURNING variant_id INTO v_variant_id;

            v_variant_rows := v_variant_rows + 1;
        END LOOP;

        IF MOD(c.rn, 1000) = 0 THEN
            DBMS_OUTPUT.PUT_LINE('  components with variants processed: ' || c.rn || ', variant rows: ' || v_variant_rows);
        END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('BOM_COMPONENT_VARIANTS loaded. Rows inserted: ' || v_variant_rows);
END;
/
