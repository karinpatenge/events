--==============================================================================
--  03_bom_json_demo_review_addons.sql
--  Optional JSON-focused add-ons for the BOM demo schema/data.
--
--  Purpose:
--    * Add path-targeted JSON_VALUE indexes for common demo predicates.
--    * Provide SQL/JSON demo queries that combine relational joins with
--      native JSON columns in Oracle AI Database 26ai.
--
--  Run after:
--    @01_create_schema.sql
--    @02_populate_bom_demo.sql
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Recreating optional JSON path indexes ===

DECLARE
    PROCEDURE drop_index_if_exists(p_index_name IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE 'DROP INDEX IF EXISTS ' || DBMS_ASSERT.SIMPLE_SQL_NAME(p_index_name);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -1418 THEN -- ORA-01418: specified index does not exist
                RAISE;
            END IF;
    END;
BEGIN
    drop_index_if_exists('IX_BOM_COMP_ASIL_JSON');
    drop_index_if_exists('IX_BOM_COMP_COO_JSON');
    drop_index_if_exists('IX_BOM_ITEM_CRIT_JSON');
    drop_index_if_exists('IX_BOM_VAR_DRIVE_JSON');
    drop_index_if_exists('IX_BOM_HEADER_LINE_JSON');
END;
/

-- Targeted scalar JSON paths. These are useful for predictable demo filters.
CREATE INDEX IF NOT EXISTS ix_bom_comp_asil_json
    ON bom_components (
        JSON_VALUE(compliance, '$.regulatory.functionalSafetyLevel' RETURNING VARCHAR2(20))
    );

CREATE INDEX IF NOT EXISTS ix_bom_comp_coo_json
    ON bom_components (
        JSON_VALUE(compliance, '$.homologation.countryOfOrigin' RETURNING VARCHAR2(2))
    );

CREATE INDEX IF NOT EXISTS ix_bom_item_crit_json
    ON bom_items (
        JSON_VALUE(item_attributes, '$.quality.criticality' RETURNING VARCHAR2(20))
    );

CREATE INDEX IF NOT EXISTS ix_bom_var_drive_json
    ON bom_component_variants (
        JSON_VALUE(variant_attributes, '$.attributes.driveSide' RETURNING VARCHAR2(3))
    );

CREATE INDEX IF NOT EXISTS ix_bom_header_line_json
    ON bom_headers (
        JSON_VALUE(bom_metadata, '$.plant.line' RETURNING VARCHAR2(20))
    );


-- Optional broader indexes for ad hoc JSON search demos.
-- Uncomment when Oracle Text / JSON search index privileges are available.
DROP INDEX IF EXISTS sx_bom_comp_specs_json;
DROP INDEX IF EXISTS sx_bom_comp_compliance_json;
DROP INDEX IF EXISTS sx_bom_header_meta_json;
CREATE SEARCH INDEX IF NOT EXISTS sx_bom_comp_specs_json ON bom_components(specifications) FOR JSON;
CREATE SEARCH INDEX IF NOT EXISTS sx_bom_comp_compliance_json ON bom_components(compliance) FOR JSON;
CREATE SEARCH INDEX IF NOT EXISTS sx_bom_header_meta_json ON bom_headers(bom_metadata) FOR JSON;

PROMPT
PROMPT === Demo 1: relational + JSON_VALUE safety-critical components ===

COLUMN part_number FORMAT A22
COLUMN component_name FORMAT A55
COLUMN category_name FORMAT A30
COLUMN asil FORMAT A10
COLUMN country FORMAT A8
COLUMN carbon_kg FORMAT 999,999.99

SELECT c.part_number,
       c.component_name,
       ca.category_name,
       JSON_VALUE(c.compliance, '$.regulatory.functionalSafetyLevel' RETURNING VARCHAR2(20)) AS asil,
       JSON_VALUE(c.compliance, '$.homologation.countryOfOrigin' RETURNING VARCHAR2(2)) AS country,
       JSON_VALUE(c.compliance, '$.sustainability.estimatedCarbonKgCo2e' RETURNING NUMBER) AS carbon_kg
FROM   bom_components c
       JOIN bom_categories ca ON ca.category_id = c.category_id
WHERE  JSON_VALUE(c.compliance, '$.regulatory.functionalSafetyLevel' RETURNING VARCHAR2(20)) IN ('ASIL-C', 'ASIL-D')
ORDER  BY carbon_kg DESC
FETCH FIRST 20 ROWS ONLY;

PROMPT
PROMPT === Demo 2: JSON_EXISTS over target-market array ===

COLUMN bom_code FORMAT A26
COLUMN vehicle_model FORMAT A24
COLUMN trim_level FORMAT A16
COLUMN plant_code FORMAT A12

SELECT h.bom_code,
       h.vehicle_model,
       h.model_year,
       h.trim_level,
       h.powertrain_type,
       h.plant_code,
       JSON_VALUE(h.bom_metadata, '$.plant.line' RETURNING VARCHAR2(20)) AS assembly_line
FROM   bom_headers h
WHERE  JSON_EXISTS(h.bom_metadata, '$.commercialTargets.targetMarkets[*]?(@ == "EU")')
AND    h.bom_status = 'RELEASED'
ORDER  BY h.model_year, h.vehicle_model
FETCH FIRST 20 ROWS ONLY;

PROMPT
PROMPT === Demo 3: JSON_TABLE projects target-market arrays into rows ===

COLUMN market_code FORMAT A12
COLUMN bom_count FORMAT 999,999

SELECT jt.market_code,
       h.powertrain_type,
       COUNT(*) AS bom_count
FROM   bom_headers h,
       JSON_TABLE(
           h.bom_metadata,
           '$.commercialTargets.targetMarkets[*]'
           COLUMNS (
               market_code VARCHAR2(10) PATH '$'
           )
       ) jt
GROUP  BY jt.market_code, h.powertrain_type
ORDER  BY jt.market_code, h.powertrain_type;

PROMPT
PROMPT === Demo 4: JSON_TABLE projects variant trim applicability arrays ===

COLUMN trim_applicability FORMAT A20
COLUMN region_code FORMAT A10
COLUMN variant_count FORMAT 999,999

SELECT v.region_code,
       jt.trim_applicability,
       COUNT(*) AS variant_count
FROM   bom_component_variants v,
       JSON_TABLE(
           v.variant_attributes,
           '$.trimApplicability[*]'
           COLUMNS (
               trim_applicability VARCHAR2(20) PATH '$'
           )
       ) jt
GROUP  BY v.region_code, jt.trim_applicability
ORDER  BY v.region_code, jt.trim_applicability;

PROMPT
PROMPT === Demo 5: BOM hierarchy with JSON item criticality ===

COLUMN tree_line FORMAT A120
COLUMN criticality FORMAT A14
COLUMN traceability FORMAT A14

SELECT LPAD(' ', (bi.level_num - 1) * 2) || bi.find_number || '  ' || c.part_number || '  ' || c.component_name AS tree_line,
       bi.quantity,
       bi.level_num,
       JSON_VALUE(bi.item_attributes, '$.quality.criticality' RETURNING VARCHAR2(20)) AS criticality,
       JSON_VALUE(bi.item_attributes, '$.quality.traceability' RETURNING VARCHAR2(20)) AS traceability
FROM   bom_items bi
       JOIN bom_components c ON c.component_id = bi.component_id
WHERE  bi.bom_id = (SELECT MIN(bom_id) FROM bom_headers WHERE bom_status = 'RELEASED')
ORDER  BY bi.sequence_num;

PROMPT
PROMPT === Demo 6: JSON aggregation / serialization of a BOM as a document ===

COLUMN bom_document FORMAT A160

WITH sample_bom AS (
    SELECT MIN(bom_id) AS bom_id
    FROM   bom_headers
    WHERE  bom_status = 'RELEASED'
),
item_summary AS (
    SELECT bi.bom_id,
           COUNT(*) AS item_count,
           MAX(bi.level_num) AS max_level
    FROM   bom_items bi
           JOIN sample_bom sb ON sb.bom_id = bi.bom_id
    GROUP  BY bi.bom_id
)
SELECT JSON_SERIALIZE(
           JSON_OBJECT(
               'bomCode' VALUE h.bom_code,
               'vehicleModel' VALUE h.vehicle_model,
               'modelYear' VALUE h.model_year,
               'trimLevel' VALUE h.trim_level,
               'powertrainType' VALUE h.powertrain_type,
               'metadata' VALUE h.bom_metadata,
               'itemCount' VALUE s.item_count,
               'maxLevel' VALUE s.max_level
               RETURNING JSON
           )
           RETURNING VARCHAR2(4000) PRETTY
       ) AS bom_document
FROM   bom_headers h
       JOIN item_summary s ON s.bom_id = h.bom_id;

PROMPT
PROMPT === Demo 7: JSON_DATAGUIDE sample for component specifications ===

COLUMN specifications_dataguide FORMAT A160

SELECT JSON_DATAGUIDE(
           specifications,
           DBMS_JSON.FORMAT_HIERARCHICAL,
           DBMS_JSON.PRETTY
       ) AS specifications_dataguide
FROM   bom_components;

PROMPT
PROMPT === Optional JSON_TRANSFORM pattern for surgical JSON update ===
PROMPT -- Example only; keep commented for read-only customer demos.
PROMPT -- UPDATE bom_components
PROMPT -- SET    compliance = JSON_TRANSFORM(
PROMPT --            compliance,
PROMPT --            SET '$.audit.lastReviewedBy' = 'bom-demo',
PROMPT --            SET '$.audit.reviewedAt' = SYSTIMESTAMP FORMAT JSON
PROMPT --        )
PROMPT -- WHERE  component_id = (SELECT MIN(component_id) FROM bom_components);
