--==============================================================================
--  02_07_load_bom_headers_items.sql
--  Load ~1,000 BOM headers and 44,000 hierarchical BOM items up to level 7.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Loading BOM_HEADERS and BOM_ITEMS ===

DECLARE
    c_bom_count CONSTANT PLS_INTEGER := 1000;

    v_model         VARCHAR2(100);
    v_trim          VARCHAR2(50);
    v_plant         VARCHAR2(20);
    v_ptype         VARCHAR2(20);
    v_bom_id        NUMBER;
    v_bom_code      VARCHAR2(50);
    v_top_component NUMBER;
    v_header_meta   VARCHAR2(32767);
    v_top_item      NUMBER;
    v_system_item   NUMBER;
    v_sub_item      NUMBER;
    v_leaf_item     NUMBER;
    v_chain_item    NUMBER;
    v_parent_chain  NUMBER;
    v_seq_num       PLS_INTEGER;
    v_sys_cat       VARCHAR2(20);
    v_sub_cat       VARCHAR2(20);
    v_leaf_cat      VARCHAR2(20);
BEGIN
    bom_demo_bom_pkg.reset_caches;
    DBMS_OUTPUT.PUT_LINE('Loading ' || c_bom_count || ' BOM headers and hierarchical items...');

    FOR i IN 1 .. c_bom_count LOOP
        v_ptype         := bom_demo_pick_pkg.pick_powertrain(i);
        v_model         := bom_demo_pick_pkg.pick_model(i);
        v_trim          := bom_demo_pick_pkg.pick_trim(i);
        v_plant         := bom_demo_pick_pkg.pick_plant(i);
        v_bom_code      := 'BOM-' || TO_CHAR(2024 + MOD(i, 5)) || '-' || bom_demo_pick_pkg.short_code(v_model) || '-' || bom_demo_pick_pkg.short_code(v_ptype) || '-' || LPAD(i, 4, '0');
        v_top_component := bom_demo_bom_pkg.choose_component('VEH', v_ptype, i);
        v_header_meta   := bom_demo_bom_pkg.make_header_metadata(v_bom_code, v_model, v_ptype, 2024 + MOD(i, 5), v_trim, v_plant, i);

        INSERT INTO bom_headers (
            bom_code, bom_name, vehicle_model, model_year, trim_level,
            powertrain_type, plant_code, top_component_id, effective_date,
            expiration_date, bom_status, bom_metadata
        ) VALUES (
            v_bom_code,
            v_model || ' ' || v_ptype || ' ' || v_trim || ' BOM MY' || TO_CHAR(2024 + MOD(i, 5)),
            v_model,
            2024 + MOD(i, 5),
            v_trim,
            v_ptype,
            v_plant,
            v_top_component,
            ADD_MONTHS(DATE '2023-01-01', MOD(i, 36)),
            CASE WHEN MOD(i, 11) = 0 THEN ADD_MONTHS(DATE '2026-01-01', MOD(i, 24)) ELSE NULL END,
            CASE WHEN MOD(i, 41) = 0 THEN 'DRAFT'
                 WHEN MOD(i, 73) = 0 THEN 'SUPERSEDED'
                 ELSE 'RELEASED'
            END,
            JSON(v_header_meta)
        ) RETURNING bom_id INTO v_bom_id;

        v_seq_num := 10;
        bom_demo_bom_pkg.add_item(v_bom_id, NULL, 'VEH', v_ptype, 1, v_seq_num, '0010', 1, i, v_top_item);

        FOR s IN 1 .. 8 LOOP
            v_sys_cat := bom_demo_bom_pkg.major_system_cat(v_ptype, s);
            v_seq_num := v_seq_num + 10;
            bom_demo_bom_pkg.add_item(v_bom_id, v_top_item, v_sys_cat, v_ptype, 2, v_seq_num, LPAD(v_seq_num, 4, '0'), 1, i * 1000 + s * 100, v_system_item);

            FOR sub IN 1 .. 2 LOOP
                v_sub_cat := bom_demo_bom_pkg.subsystem_cat(v_ptype, s, sub);
                v_seq_num := v_seq_num + 10;
                bom_demo_bom_pkg.add_item(v_bom_id, v_system_item, v_sub_cat, v_ptype, 3, v_seq_num, LPAD(v_seq_num, 4, '0'), 1, i * 1000 + s * 100 + sub * 10, v_sub_item);

                v_leaf_cat := bom_demo_bom_pkg.leaf_cat(v_ptype, s, sub);
                v_seq_num := v_seq_num + 10;
                bom_demo_bom_pkg.add_item(
                    v_bom_id, v_sub_item, v_leaf_cat, v_ptype, 4, v_seq_num,
                    LPAD(v_seq_num, 4, '0'),
                    CASE WHEN v_leaf_cat = 'FASTENER' THEN 4 + MOD(i + s + sub, 6)
                         WHEN v_leaf_cat = 'FLUID' THEN ROUND(0.5 + MOD(i + s + sub, 10) * 0.25, 4)
                         ELSE 1
                    END,
                    i * 1000 + s * 100 + sub * 10 + 1,
                    v_leaf_item
                );

                IF s = 1 AND sub = 1 THEN
                    v_parent_chain := v_leaf_item;

                    v_seq_num := v_seq_num + 10;
                    bom_demo_bom_pkg.add_item(v_bom_id, v_parent_chain, 'SENSOR', v_ptype, 5, v_seq_num, LPAD(v_seq_num, 4, '0'), 1, i * 1000 + 501, v_chain_item);
                    v_parent_chain := v_chain_item;

                    v_seq_num := v_seq_num + 10;
                    bom_demo_bom_pkg.add_item(v_bom_id, v_parent_chain, 'HARNESS', v_ptype, 6, v_seq_num, LPAD(v_seq_num, 4, '0'), 1, i * 1000 + 601, v_chain_item);
                    v_parent_chain := v_chain_item;

                    v_seq_num := v_seq_num + 10;
                    bom_demo_bom_pkg.add_item(v_bom_id, v_parent_chain, 'FASTENER', v_ptype, 7, v_seq_num, LPAD(v_seq_num, 4, '0'), 2 + MOD(i, 5), i * 1000 + 701, v_chain_item);
                END IF;
            END LOOP;
        END LOOP;

        IF MOD(i, 100) = 0 THEN
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('  BOMs loaded: ' || i);
        END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('BOM_HEADERS and BOM_ITEMS loaded.');
END;
/
