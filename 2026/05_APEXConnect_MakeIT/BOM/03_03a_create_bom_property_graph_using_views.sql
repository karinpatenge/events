--==============================================================================
--  03_03a_create_bom_property_graph_using_views.sql
--  SQL Property Graph DDL for the BOM demo schema
--  Target: Oracle AI Database 26ai
--
--  The graph uses the original non-JSON lookup table directly and uses the
--  <original_table_name>_vw views for tables that contain JSON columns.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

PROMPT
PROMPT === Dropping BOM_GRAPH_EXPANDED ===

DROP PROPERTY GRAPH IF EXISTS bom_graph_expanded;

PROMPT
PROMPT === Creating BOM_GRAPH_EXPANDED ===

CREATE PROPERTY GRAPH IF NOT EXISTS bom_graph_expanded
  VERTEX TABLES (
    bom_categories
      KEY (category_id)
      LABEL category
      PROPERTIES ARE ALL COLUMNS,
    bom_components_vw AS bom_components
      KEY (component_id)
      LABEL component
      PROPERTIES ARE ALL COLUMNS,
    bom_component_revisions_vw AS bom_component_revisions
      KEY (revision_id)
      LABEL component_revision
      PROPERTIES ARE ALL COLUMNS,
    bom_component_variants_vw AS bom_component_variants
      KEY (variant_id)
      LABEL component_variant
      PROPERTIES ARE ALL COLUMNS,
    bom_headers_vw AS bom_headers
      KEY (bom_id)
      LABEL header
      PROPERTIES ARE ALL COLUMNS,
    bom_items_vw AS bom_items
      KEY (bom_item_id)
      LABEL item
      PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    bom_items_vw AS bom_items_bom_items
      KEY (bom_item_id)
      SOURCE KEY (parent_item_id) REFERENCES bom_items (bom_item_id)
      DESTINATION KEY (bom_item_id) REFERENCES bom_items (bom_item_id)
      LABEL contains_item
      NO PROPERTIES,
    bom_items_vw AS bom_items_bom_headers
      KEY (bom_item_id)
      SOURCE KEY (bom_id) REFERENCES bom_headers (bom_id)
      DESTINATION KEY (bom_item_id) REFERENCES bom_items (bom_item_id)
      LABEL has_item
      NO PROPERTIES,
    bom_items_vw AS bom_items_bom_component_variants
      KEY (bom_item_id)
      SOURCE KEY (bom_item_id) REFERENCES bom_items (bom_item_id)
      DESTINATION KEY (variant_id) REFERENCES bom_component_variants (variant_id)
      LABEL has_variant
      NO PROPERTIES,
    bom_items_vw AS bom_items_bom_components
      KEY (bom_item_id)
      SOURCE KEY (bom_item_id) REFERENCES bom_items (bom_item_id)
      DESTINATION KEY (component_id) REFERENCES bom_components (component_id)
      LABEL uses_component
      NO PROPERTIES,
    bom_items_vw AS bom_items_bom_component_revisions
      KEY (bom_item_id)
      SOURCE KEY (bom_item_id) REFERENCES bom_items (bom_item_id)
      DESTINATION KEY (revision_id) REFERENCES bom_component_revisions (revision_id)
      LABEL uses_revision
      NO PROPERTIES,
    bom_components_vw AS bom_components_bom_categories
      KEY (component_id)
      SOURCE KEY (component_id) REFERENCES bom_components (component_id)
      DESTINATION KEY (category_id) REFERENCES bom_categories (category_id)
      LABEL in_category
      NO PROPERTIES,
    bom_component_revisions_vw AS bom_components_bom_components_revisions
      KEY (revision_id)
      SOURCE KEY (component_id) REFERENCES bom_components (component_id)
      DESTINATION KEY (revision_id) REFERENCES bom_component_revisions (revision_id)
      LABEL has_revision
      NO PROPERTIES,
    bom_component_variants_vw AS bom_components_bom_component_variants
      KEY (variant_id)
      SOURCE KEY (component_id) REFERENCES bom_components (component_id)
      DESTINATION KEY (variant_id) REFERENCES bom_component_variants (variant_id)
      LABEL has_variant
      NO PROPERTIES,
    bom_headers_vw AS bom_headers_bom_components
      KEY (bom_id)
      SOURCE KEY (bom_id) REFERENCES bom_headers (bom_id)
      DESTINATION KEY (top_component_id) REFERENCES bom_components (component_id)
      LABEL has_top_component
      NO PROPERTIES
  )
  -- ENFORCED MODE is not supported when graph element tables are views.
  OPTIONS (TRUSTED MODE, ALLOW MIXED PROPERTY TYPES);

COMMENT ON PROPERTY GRAPH bom_ai_property_graph IS
    'BOM SQL property graph using first-level JSON Data Guide projection views.';

PROMPT
PROMPT === SQL property graph created ===

SELECT graph_name
FROM   user_property_graphs
WHERE  graph_name = 'BOM_GRAPH_EXPANDED';

PROMPT
PROMPT === Graph elements ===

SELECT graph_name, element_name, element_kind
FROM   user_pg_elements
WHERE  graph_name = 'BOM_GRAPH_EXPANDED'
ORDER  BY element_kind, element_name;
