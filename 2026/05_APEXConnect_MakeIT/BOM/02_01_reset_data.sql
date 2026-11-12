--==============================================================================
--  02_01_reset_data.sql
--  Delete existing BOM demo data in dependency order.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Resetting BOM demo data ===

TRUNCATE TABLE bom_items DROP STORAGE;
TRUNCATE TABLE bom_headers DROP STORAGE;
TRUNCATE TABLE bom_component_variants DROP STORAGE;
TRUNCATE TABLE bom_component_revisions DROP STORAGE;
TRUNCATE TABLE bom_components DROP STORAGE;
TRUNCATE TABLE bom_categories DROP STORAGE;

COMMIT;

PROMPT === Existing BOM demo rows deleted ===
