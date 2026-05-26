--==============================================================================
--  02_08_validate_bom_data.sql
--  Row counts, hierarchy validation, and JSON readability samples.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Row counts ===
COLUMN table_name FORMAT A35
COLUMN rows_loaded FORMAT 999,999,999
SELECT 'BOM_CATEGORIES' table_name, COUNT(*) rows_loaded FROM bom_categories
UNION ALL SELECT 'BOM_COMPONENTS', COUNT(*) FROM bom_components
UNION ALL SELECT 'BOM_COMPONENT_REVISIONS', COUNT(*) FROM bom_component_revisions
UNION ALL SELECT 'BOM_COMPONENT_VARIANTS', COUNT(*) FROM bom_component_variants
UNION ALL SELECT 'BOM_HEADERS', COUNT(*) FROM bom_headers
UNION ALL SELECT 'BOM_ITEMS', COUNT(*) FROM bom_items
ORDER BY table_name;

PROMPT
PROMPT === BOM hierarchy validation ===
SELECT MAX(level_num) AS max_level,
       COUNT(DISTINCT bom_id) AS boms_with_items,
       COUNT(DISTINCT CASE WHEN level_num = 7 THEN bom_id END) AS boms_reaching_level_7,
       COUNT(*) AS total_items
FROM   bom_items;

PROMPT
PROMPT === Sample components with native JSON serialized for readability ===
COLUMN part_number FORMAT A18
COLUMN component_name FORMAT A55
COLUMN specs FORMAT A100
SELECT part_number,
       component_name,
       JSON_SERIALIZE(specifications RETURNING VARCHAR2(4000) PRETTY) AS specs
FROM   bom_components
WHERE  ROWNUM <= 3;

PROMPT
PROMPT === Sample BOM tree ===
COLUMN tree_line FORMAT A120
SELECT LPAD(' ', (level_num - 1) * 2) || bi.find_number || '  ' || c.part_number || '  ' || c.component_name AS tree_line,
       bi.quantity,
       bi.level_num
FROM   bom_items bi
       JOIN bom_components c ON c.component_id = bi.component_id
WHERE  bi.bom_id = (SELECT MIN(bom_id) FROM bom_headers)
ORDER  BY bi.sequence_num;
