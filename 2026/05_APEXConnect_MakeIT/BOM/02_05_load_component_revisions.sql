--==============================================================================
--  02_05_load_component_revisions.sql
--  Load engineering revisions for each component.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Loading BOM_COMPONENT_REVISIONS ===

DECLARE
    v_revision_id NUMBER;
    v_rev_count   PLS_INTEGER;
    v_rev_code    VARCHAR2(10);
    v_rev_status  VARCHAR2(20);
    v_rev_date    DATE;
    v_engineer    VARCHAR2(100);
    v_specs       VARCHAR2(32767);
BEGIN
    bom_demo_bom_pkg.reset_caches;
    DBMS_OUTPUT.PUT_LINE('Loading component revisions...');

    FOR c IN (
        SELECT c.component_id,
               c.part_number,
               c.lifecycle_status,
               ca.category_code,
               ROW_NUMBER() OVER (ORDER BY c.component_id) rn
        FROM   bom_components c
               JOIN bom_categories ca ON ca.category_id = c.category_id
        ORDER  BY c.component_id
    ) LOOP
        v_rev_count := 1 + MOD(c.rn, 4);

        FOR r IN 1 .. v_rev_count LOOP
            v_rev_code := CHR(64 + r);
            v_rev_date := ADD_MONTHS(DATE '2021-01-15', MOD(c.rn, 48)) + (r * 31);

            IF r < v_rev_count THEN
                v_rev_status := 'SUPERSEDED';
            ELSIF c.lifecycle_status = 'OBSOLETE' THEN
                v_rev_status := 'OBSOLETE';
            ELSIF c.lifecycle_status = 'PROTOTYPE' THEN
                v_rev_status := CASE WHEN MOD(c.rn, 2) = 0 THEN 'DRAFT' ELSE 'IN_REVIEW' END;
            ELSE
                v_rev_status := 'RELEASED';
            END IF;

            v_specs    := bom_demo_component_json_pkg.make_revision_specs(c.category_code, v_rev_code, c.rn, r);
            v_engineer := bom_demo_pick_pkg.pick_engineer(c.rn + r);

            INSERT INTO bom_component_revisions (
                component_id, revision_code, revision_date, eco_number,
                engineer_name, change_summary, revision_status, specifications
            ) VALUES (
                c.component_id, v_rev_code, v_rev_date,
                'ECO-' || TO_CHAR(EXTRACT(YEAR FROM v_rev_date)) || '-' || LPAD(c.rn * 10 + r, 6, '0'),
                v_engineer,
                CASE r
                    WHEN 1 THEN 'Initial engineering release for ' || c.part_number
                    ELSE 'Revision ' || v_rev_code || ' updates validation, manufacturability and regional compliance for ' || c.part_number
                END,
                v_rev_status,
                JSON(v_specs)
            ) RETURNING revision_id INTO v_revision_id;
        END LOOP;

        IF MOD(c.rn, 1000) = 0 THEN
            DBMS_OUTPUT.PUT_LINE('  component revisions processed: ' || c.rn);
        END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('BOM_COMPONENT_REVISIONS loaded.');
END;
/
