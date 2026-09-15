--==============================================================================
--  02-run_all_populate_bom_demo.sql
--  Last update: 2026-08-28
--
--  Run all individual 02_0*.sql BOM demo scripts in dependency order.
--
--  Prerequisite: run 01-create_schema.sql first as BOMUSER.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT
PROMPT === Running all 02_0*.sql BOM demo scripts ===

@@02_01-reset_data.sql
@@02_02a-create_json_helpers.sql
@@02_02b-create_picklist_helpers.sql
@@02_02c-create_component_json_helpers.sql
@@02_02d-create_bom_hierarchy_helpers.sql
@@02_02-validate_packages.sql
@@02_03-load_categories.sql
@@02_04-load_components.sql
@@02_05-load_component_revisions.sql
@@02_06-load_component_variants.sql
@@02_07-load_bom_headers_items.sql
@@02_08-validate_bom_data.sql

PROMPT
PROMPT === All 02_0*.sql BOM demo scripts complete ===
