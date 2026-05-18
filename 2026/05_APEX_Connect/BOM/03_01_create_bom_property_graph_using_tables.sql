-------------------------------------------
-- Create SQL Property Graph for BoM tables
-- including JSON columns
-- by referring to the original tables
-------------------------------------------

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

PROMPT
PROMPT === Dropping BOM_GRAPH ===

DROP PROPERTY GRAPH IF EXISTS bom_graph;

PROMPT
PROMPT === Creating BOM_GRAPH ===

CREATE PROPERTY GRAPH IF NOT EXISTS bom_graph
  VERTEX TABLES (
    bom_categories
      KEY ( category_id )
      LABEL category
      PROPERTIES ARE ALL COLUMNS,
    bom_items
      KEY ( bom_item_id )
      LABEL item
      PROPERTIES ARE ALL COLUMNS,
    bom_component_variants
      KEY ( variant_id )
      LABEL component_variant
      PROPERTIES ARE ALL COLUMNS,
    bom_components
      KEY ( component_id )
      LABEL component
      PROPERTIES ARE ALL COLUMNS,
    bom_headers
      KEY ( bom_id )
      LABEL header
      PROPERTIES ARE ALL COLUMNS,
    bom_component_revisions
      KEY ( revision_id )
      LABEL component_revision
      PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    bom_items AS bom_items_bom_items
      KEY ( bom_item_id )
      SOURCE KEY (parent_item_id) REFERENCES bom_items (bom_item_id)
      DESTINATION KEY (bom_item_id) REFERENCES bom_items (bom_item_id)
      LABEL contains_item
      NO PROPERTIES,
    bom_items AS bom_items_bom_headers
      KEY ( bom_item_id )
      SOURCE KEY (bom_id) REFERENCES bom_headers (bom_id)
      DESTINATION KEY (bom_item_id) REFERENCES bom_items (bom_item_id)
      LABEL has_item
      NO PROPERTIES,
    bom_items AS bom_items_bom_component_variants
      KEY ( bom_item_id )
      SOURCE KEY ( bom_item_id ) REFERENCES bom_items( bom_item_id )
      DESTINATION KEY ( variant_id ) REFERENCES bom_component_variants( variant_id )
      LABEL has_variant
      NO PROPERTIES,
    bom_items AS bom_items_bom_components
      KEY ( bom_item_id )
      SOURCE KEY ( bom_item_id ) REFERENCES bom_items( bom_item_id )
      DESTINATION KEY ( component_id ) REFERENCES bom_components( component_id )
      LABEL uses_component
      NO PROPERTIES,
    bom_items AS bom_items_bom_component_revisions
      KEY ( bom_item_id )
      SOURCE KEY ( bom_item_id ) REFERENCES bom_items( bom_item_id )
      DESTINATION KEY ( revision_id ) REFERENCES bom_component_revisions( revision_id )
      LABEL uses_revision
      NO PROPERTIES,
    bom_components AS bom_components_bom_categories
      KEY ( component_id )
      SOURCE KEY ( component_id ) REFERENCES bom_components( component_id )
      DESTINATION KEY ( category_id ) REFERENCES bom_categories( category_id )
      LABEL in_category
      NO PROPERTIES,
    bom_component_variants AS bom_components_bom_component_variants
      KEY ( variant_id )
      SOURCE KEY (component_id) REFERENCES bom_components (component_id)
      DESTINATION KEY (variant_id) REFERENCES bom_component_variants (variant_id)
      LABEL has_variant
      NO PROPERTIES,
    bom_headers AS bom_headers_bom_components
      KEY ( bom_id )
      SOURCE KEY ( bom_id ) REFERENCES bom_headers( bom_id )
      DESTINATION KEY ( top_component_id ) REFERENCES bom_components( component_id )
      LABEL has_top_component
      NO PROPERTIES,
    bom_component_revisions AS bom_component_bom_components_revisions
      KEY ( revision_id )
      SOURCE KEY (component_id) REFERENCES bom_components (component_id)
      DESTINATION KEY (revision_id) REFERENCES bom_component_revisions (revision_id)
      LABEL has_revision
      NO PROPERTIES
  );