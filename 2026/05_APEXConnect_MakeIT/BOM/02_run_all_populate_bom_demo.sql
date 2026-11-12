--==============================================================================
--  02_run_all_populate_bom_demo.sql
--  Run all split BOM demo population scripts in order.
--
--  Prerequisite: run 01_create_schema.sql first in the same schema.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT
PROMPT === Running split BOM demo data load ===

@@02_01_reset_data.sql
@@02_02a_create_json_helpers.sql
@@02_02b_create_picklist_helpers.sql
@@02_02c_create_component_json_helpers.sql
@@02_02d_create_bom_hierarchy_helpers.sql
@@02_03_load_categories.sql
@@02_04_load_components.sql
@@02_05_load_component_revisions.sql
@@02_06_load_component_variants.sql
@@02_07_load_bom_headers_items.sql
@@02_08_validate_bom_data.sql
@@02_09_bom_json_demo_review_addons.sql

PROMPT
PROMPT === Split BOM demo data load complete ===
