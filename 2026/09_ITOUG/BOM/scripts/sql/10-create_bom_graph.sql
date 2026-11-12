--==============================================================================
--  10-create_bom_graph.sql
--  Last update: 2026-08-28

--  Create the BOM SQL Property Graph from BOMUSER primary and foreign keys.
--
--  Run as BOMUSER after 01-create_schema.sql.
--  Every graph element uses its underlying table primary key. TRUSTED MODE is
--  required because some foreign keys are nullable and child rows are graph
--  sources for their relationships.
--
--  Note:
--  JSON columns are excluded as properties. Will be added later.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Creating BOM_GRAPH ===

CREATE OR REPLACE PROPERTY GRAPH bom_graph
  VERTEX TABLES (
    bom_categories AS category
      KEY (category_id)
      LABEL category
        PROPERTIES ARE ALL COLUMNS,
    bom_components AS component
      KEY (component_id)
      LABEL component
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          specifications,
          compliance
        ),
    bom_component_revisions AS component_revision
      KEY (revision_id)
      LABEL component_revision
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          specifications
        ),
    bom_component_variants AS component_variant
      KEY (variant_id)
      LABEL component_variant
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          variant_attributes
        ),
    bom_headers AS bom_header
      KEY (bom_id)
      LABEL bom_header
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          bom_metadata
        ),
    bom_items AS bom_item
      KEY (bom_item_id)
      LABEL bom_item
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          item_attributes
        )
  )
  EDGE TABLES (
    bom_components AS component_category_edge
      KEY (component_id)
      SOURCE KEY (component_id)
        REFERENCES component (component_id)
      DESTINATION KEY (category_id)
        REFERENCES category (category_id)
      LABEL component_category
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          specifications,
          compliance
        ),
    bom_component_revisions AS component_revision_edge
      KEY (revision_id)
      SOURCE KEY (revision_id)
        REFERENCES component_revision (revision_id)
      DESTINATION KEY (component_id)
        REFERENCES component (component_id)
      LABEL component_revision
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          specifications
        ),
    bom_component_variants AS component_variant_edge
      KEY (variant_id)
      SOURCE KEY (variant_id)
        REFERENCES component_variant (variant_id)
      DESTINATION KEY (component_id)
        REFERENCES component (component_id)
      LABEL component_variant
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          variant_attributes
        ),
    bom_headers AS bom_top_component_edge
      KEY (bom_id)
      SOURCE KEY (bom_id)
        REFERENCES bom_header (bom_id)
      DESTINATION KEY (top_component_id)
        REFERENCES component (component_id)
      LABEL bom_top_component
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          bom_metadata
        ),
    bom_items AS bom_item_bom_edge
      KEY (bom_item_id)
      SOURCE KEY (bom_item_id)
        REFERENCES bom_item (bom_item_id)
      DESTINATION KEY (bom_id)
        REFERENCES bom_header (bom_id)
      LABEL bom_item_bom
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          item_attributes
        ),
    bom_items AS bom_item_parent_edge
      KEY (bom_item_id)
      SOURCE KEY (bom_item_id)
        REFERENCES bom_item (bom_item_id)
      DESTINATION KEY (parent_item_id)
        REFERENCES bom_item (bom_item_id)
      LABEL bom_item_parent
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          item_attributes
        ),
    bom_items AS bom_item_component_edge
      KEY (bom_item_id)
      SOURCE KEY (bom_item_id)
        REFERENCES bom_item (bom_item_id)
      DESTINATION KEY (component_id)
        REFERENCES component (component_id)
      LABEL bom_item_component
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          item_attributes
        ),
    bom_items AS bom_item_revision_edge
      KEY (bom_item_id)
      SOURCE KEY (bom_item_id)
        REFERENCES bom_item (bom_item_id)
      DESTINATION KEY (revision_id)
        REFERENCES component_revision (revision_id)
      LABEL bom_item_revision
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          item_attributes
        ),
    bom_items AS bom_item_variant_edge
      KEY (bom_item_id)
      SOURCE KEY (bom_item_id)
        REFERENCES bom_item (bom_item_id)
      DESTINATION KEY (variant_id)
        REFERENCES component_variant (variant_id)
      LABEL bom_item_variant
        PROPERTIES ARE ALL COLUMNS EXCEPT (
          item_attributes
        )
  )
  OPTIONS (TRUSTED MODE);

PROMPT
PROMPT === BOM_GRAPH created ===
