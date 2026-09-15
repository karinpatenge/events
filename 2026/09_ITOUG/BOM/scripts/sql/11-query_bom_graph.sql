--==============================================================================
--  11-query_bom_graph.sql
--  Last update: 2026-08-28

--  Query BOM_GRAPH for visualization, BOM impact, and graph algorithm analysis.
--
--  Run as BOMUSER after 10-create_bom_graph.sql.
--  The result returns one row per edge and can be large.
--==============================================================================

PROMPT
PROMPT === Settings ===

SET ECHO ON
SET FEEDBACK ON
SET LINESIZE 500
SET PAGESIZE 200
SET DEFINE OFF

ALTER SESSION ENABLE PARALLEL QUERY;

PROMPT
PROMPT === Querying the BOM_GRAPH ===

SELECT
  source_vertex_id,
  edge_id,
  destination_vertex_id
FROM
  GRAPH_TABLE (
    bom_graph
    MATCH (source_vertex) -[edge]-> (destination_vertex)
    COLUMNS (
      VERTEX_ID(source_vertex) AS source_vertex_id,
      EDGE_ID(edge) AS edge_id,
      VERTEX_ID(destination_vertex) AS destination_vertex_id
    )
  );

--==============================================================================
--  Question 1: Which components are used by the greatest number of released
--  BOMs?
--
--  Expected result:
--    * Up to 20 components, ranked by distinct released BOM usage.
--    * RELEASED_BOM_COUNT counts each BOM header once, even when the component
--      occurs on more than one BOM item in that BOM.
--==============================================================================

PROMPT
PROMPT === Question 1: most-used components in released BOMs ===

COLUMN component_id FORMAT 999,999,999
COLUMN part_number FORMAT A30
COLUMN component_name FORMAT A60
COLUMN released_bom_count FORMAT 999,999

SELECT
  component_id,
  part_number,
  component_name,
  COUNT(DISTINCT bom_header_id) AS released_bom_count
FROM
  GRAPH_TABLE (
    bom_graph
    MATCH
      (header_node IS bom_header WHERE header_node.bom_status = 'RELEASED')
      <-[bom_item_bom_edge IS bom_item_bom]-
      (bom_item_node IS bom_item)
      -[bom_item_component_edge IS bom_item_component]->
      (component_node IS component)
    COLUMNS (
      header_node.bom_id AS bom_header_id,
      component_node.component_id AS component_id,
      component_node.part_number AS part_number,
      component_node.component_name AS component_name
    )
  )
GROUP BY
  component_id,
  part_number,
  component_name
ORDER BY
  released_bom_count DESC,
  part_number
FETCH FIRST 20 ROWS ONLY;

--==============================================================================
--  Question 2: For a selected BOM, what are the complete parent-to-child
--  BOM-item paths, and which component is used at each item?
--
--  Expected result:
--    * Every BOM item in the selected BOM appears once as an indented tree.
--    * The result includes the item's level, quantity, and component details.
--    * No rows are returned when the BOM code does not identify a BOM root.
--==============================================================================

PROMPT
PROMPT === Question 2: BOM item hierarchy ===

COLUMN bom_code FORMAT A30
COLUMN bom_name FORMAT A45
COLUMN vehicle_model FORMAT A24
COLUMN powertrain_type FORMAT A16
COLUMN bom_status FORMAT A12
COLUMN level_num FORMAT 99
COLUMN quantity FORMAT 999,999.9999
COLUMN bom_tree_line FORMAT A140

-- Select a BOM code from this list for the hierarchy query below.
PROMPT
PROMPT === Available BOM codes ===

SELECT
  bom_code,
  bom_name,
  vehicle_model,
  powertrain_type,
  bom_status
FROM
  bom_headers
ORDER BY
  bom_code
FETCH FIRST 20 ROWS ONLY;

-- Shorter:
SELECT
  bom_code || ' - ' || bom_name AS display_value,
  bom_code AS return_value
FROM
  bom_headers
ORDER BY
  bom_code;

PROMPT
PROMPT === Enter a BOM code for the hierarchy query ===
SET DEFINE ON
ACCEPT selected_bom_code CHAR PROMPT 'BOM code: '

SELECT
  bom_code,
  level_num,
  quantity,
  LPAD(
    ' ',
    (level_num - 1) * 2
  ) || find_number || '  ' || part_number || '  ' || component_name AS bom_tree_line
FROM
  GRAPH_TABLE (
    bom_graph
    MATCH
      (header_node IS bom_header WHERE header_node.bom_code = '&selected_bom_code')
      <-[bom_item_bom_edge IS bom_item_bom]-
      (root_item_node IS bom_item WHERE root_item_node.parent_item_id IS NULL)
      (<-[bom_item_parent_edge IS bom_item_parent]-){,6}
      (bom_item_node IS bom_item)
      -[bom_item_component_edge IS bom_item_component]->
      (component_node IS component)
    COLUMNS (
      header_node.bom_code AS bom_code,
      bom_item_node.level_num AS level_num,
      bom_item_node.sequence_num AS sequence_num,
      bom_item_node.find_number AS find_number,
      bom_item_node.quantity AS quantity,
      component_node.part_number AS part_number,
      component_node.component_name AS component_name
    )
  )
ORDER BY
  sequence_num;

--==============================================================================
--  Question 2 (visualization): Which vertices and edges form the selected
--  BOM hierarchy and its component assignments?
--
--  Expected result:
--    * One row per vertex-edge-vertex traversal step in the selected BOM
--      hierarchy.
--    * Each named vertex and edge in the path is returned as a native SQL
--      property graph identifier.
--    * BOM_ITEM_PARENT_EDGE_IDS is a native JSON array because the bounded
--      quantifier can match multiple parent edges.
--    * The result can be supplied directly to a graph visualization tool.
--==============================================================================

PROMPT
PROMPT === Question 2: BOM hierarchy visualization edges ===

COLUMN source_vertex_id FORMAT A160
COLUMN edge_id FORMAT A160
COLUMN destination_vertex_id FORMAT A160

SELECT
  bom_code,
  header_vertex_id,
  bom_item_bom_edge_id,
  step_source_node_vertex_id,
  step_edge_id,
  step_destination_node_vertex_id,
  bom_item_component_edge_id,
  component_node_vertex_id
FROM
  GRAPH_TABLE (
    bom_graph
    MATCH
      (header_node IS bom_header WHERE header_node.bom_code = 'BOM-2024-ASTERS-EV-0900')
      <-[bom_item_bom_edge IS bom_item_bom]-
      (root_item_node IS bom_item WHERE root_item_node.parent_item_id IS NULL)
      (<-[bom_item_parent_edge IS bom_item_parent]-){,6}
      (bom_item_node IS bom_item)
      -[bom_item_component_edge IS bom_item_component]->
      (component_node IS component)
    ONE ROW PER STEP (
      step_source_node,
      step_edge,
      step_destination_node
    )
    COLUMNS (
      header_node.bom_code AS bom_code,
      VERTEX_ID(header_node) AS header_vertex_id,
      EDGE_ID(bom_item_bom_edge) AS bom_item_bom_edge_id,
      VERTEX_ID(step_source_node) AS step_source_node_vertex_id,
      EDGE_ID(step_edge) AS step_edge_id,
      VERTEX_ID(step_destination_node) AS step_destination_node_vertex_id,
      EDGE_ID(bom_item_component_edge) AS bom_item_component_edge_id,
      VERTEX_ID(component_node) AS component_node_vertex_id
    )
  );

UNDEFINE selected_bom_code
SET DEFINE OFF

--==============================================================================
--  Question 3: Which component categories contain parts that are used in both
--  ICE (Internal Combustion Engine) and EV (Electric Vehicles) vehicle BOMs?
--
--  Expected result:
--    * Each row represents one traversal step from a shared category to an
--      ICE or EV BOM that uses one of its components.
--    * The result includes native identifiers for every vertex and edge in
--      the path, which can be used to visualize the cross-powertrain use.
--==============================================================================

PROMPT
PROMPT === Question 3: categories used in ICE and EV BOMs ===

COLUMN category_code FORMAT A20
COLUMN category_name FORMAT A40
COLUMN powertrain_type FORMAT A20
COLUMN bom_code FORMAT A30

WITH
  category_powertrain_usage AS (
    SELECT
      category_id,
      powertrain_type
    FROM
      GRAPH_TABLE (
        bom_graph
        MATCH
          (category_node IS category)
          <-[component_category_edge IS component_category]-
          (component_node IS component)
          <-[bom_item_component_edge IS bom_item_component]-
          (bom_item_node IS bom_item)
          -[bom_item_bom_edge IS bom_item_bom]->
          (header_node IS bom_header)
        COLUMNS (
          category_node.category_id AS category_id,
          header_node.powertrain_type AS powertrain_type
        )
      )
    GROUP BY
      category_id,
      powertrain_type
  ),
  shared_category AS (
    SELECT
      category_id
    FROM
      category_powertrain_usage
    WHERE
      powertrain_type IN (
        'ICE',
        'EV'
      )
    GROUP BY
      category_id
    HAVING
      COUNT(DISTINCT powertrain_type) = 2
  )
SELECT
  graph_result.category_id,
  graph_result.category_code,
  graph_result.category_name,
  graph_result.powertrain_type,
  graph_result.bom_code,
  graph_result.category_vertex_id,
  graph_result.component_category_edge_id,
  graph_result.component_vertex_id,
  graph_result.bom_item_component_edge_id,
  graph_result.bom_item_vertex_id,
  graph_result.bom_item_bom_edge_id,
  graph_result.bom_header_vertex_id,
  graph_result.source_vertex_id,
  graph_result.edge_id,
  graph_result.destination_vertex_id
FROM
  GRAPH_TABLE (
    bom_graph
    MATCH
      (category_node IS category)
      <-[component_category_edge IS component_category]-
      (component_node IS component)
      <-[bom_item_component_edge IS bom_item_component]-
      (bom_item_node IS bom_item)
      -[bom_item_bom_edge IS bom_item_bom]->
      (header_node IS bom_header WHERE header_node.powertrain_type IN (
        'ICE',
        'EV'
      ))
    ONE ROW PER STEP (
      step_source_node,
      step_edge,
      step_destination_node
    )
    COLUMNS (
      category_node.category_id AS category_id,
      category_node.category_code AS category_code,
      category_node.category_name AS category_name,
      header_node.powertrain_type AS powertrain_type,
      header_node.bom_code AS bom_code,
      VERTEX_ID(category_node) AS category_vertex_id,
      EDGE_ID(component_category_edge) AS component_category_edge_id,
      VERTEX_ID(component_node) AS component_vertex_id,
      EDGE_ID(bom_item_component_edge) AS bom_item_component_edge_id,
      VERTEX_ID(bom_item_node) AS bom_item_vertex_id,
      EDGE_ID(bom_item_bom_edge) AS bom_item_bom_edge_id,
      VERTEX_ID(header_node) AS bom_header_vertex_id,
      VERTEX_ID(step_source_node) AS source_vertex_id,
      EDGE_ID(step_edge) AS edge_id,
      VERTEX_ID(step_destination_node) AS destination_vertex_id
    )
  ) graph_result
  JOIN shared_category
    ON shared_category.category_id = graph_result.category_id
ORDER BY
  graph_result.category_code,
  graph_result.powertrain_type,
  graph_result.bom_code;

--==============================================================================
--  Question 4: Which BOMs contain components or variants that are obsolete,
--  in pilot status, or otherwise no longer active?
--
--  Expected result:
--    * Each row represents one traversal step to an affected BOM item and
--      its non-active component or variant.
--    * The native graph identifiers expose the affected BOM relationship for
--      visualization.
--==============================================================================

PROMPT
PROMPT === Question 4: BOMs with non-active components or variants ===

COLUMN issue_type FORMAT A12
COLUMN bom_code FORMAT A30
COLUMN issue_code FORMAT A50
COLUMN issue_name FORMAT A60
COLUMN issue_status FORMAT A20

SELECT
  issue_type,
  bom_code,
  issue_code,
  issue_name,
  issue_status,
  bom_header_vertex_id,
  bom_item_bom_edge_id,
  bom_item_vertex_id,
  issue_edge_id,
  issue_vertex_id,
  source_vertex_id,
  edge_id,
  destination_vertex_id
FROM
  GRAPH_TABLE (
    bom_graph
    MATCH
      (header_node IS bom_header)
      <-[bom_item_bom_edge IS bom_item_bom]-
      (bom_item_node IS bom_item)
      -[bom_item_component_edge IS bom_item_component]->
      (component_node IS component WHERE component_node.lifecycle_status <> 'ACTIVE')
    ONE ROW PER STEP (
      step_source_node,
      step_edge,
      step_destination_node
    )
    COLUMNS (
      'COMPONENT' AS issue_type,
      header_node.bom_code AS bom_code,
      component_node.part_number AS issue_code,
      component_node.component_name AS issue_name,
      component_node.lifecycle_status AS issue_status,
      VERTEX_ID(header_node) AS bom_header_vertex_id,
      EDGE_ID(bom_item_bom_edge) AS bom_item_bom_edge_id,
      VERTEX_ID(bom_item_node) AS bom_item_vertex_id,
      EDGE_ID(bom_item_component_edge) AS issue_edge_id,
      VERTEX_ID(component_node) AS issue_vertex_id,
      VERTEX_ID(step_source_node) AS source_vertex_id,
      EDGE_ID(step_edge) AS edge_id,
      VERTEX_ID(step_destination_node) AS destination_vertex_id
    )
  )
UNION ALL
SELECT
  issue_type,
  bom_code,
  issue_code,
  issue_name,
  issue_status,
  bom_header_vertex_id,
  bom_item_bom_edge_id,
  bom_item_vertex_id,
  issue_edge_id,
  issue_vertex_id,
  source_vertex_id,
  edge_id,
  destination_vertex_id
FROM
  GRAPH_TABLE (
    bom_graph
    MATCH
      (header_node IS bom_header)
      <-[bom_item_bom_edge IS bom_item_bom]-
      (bom_item_node IS bom_item)
      -[bom_item_variant_edge IS bom_item_variant]->
      (variant_node IS component_variant WHERE variant_node.variant_status <> 'ACTIVE')
    ONE ROW PER STEP (
      step_source_node,
      step_edge,
      step_destination_node
    )
    COLUMNS (
      'VARIANT' AS issue_type,
      header_node.bom_code AS bom_code,
      variant_node.variant_code AS issue_code,
      variant_node.variant_name AS issue_name,
      variant_node.variant_status AS issue_status,
      VERTEX_ID(header_node) AS bom_header_vertex_id,
      EDGE_ID(bom_item_bom_edge) AS bom_item_bom_edge_id,
      VERTEX_ID(bom_item_node) AS bom_item_vertex_id,
      EDGE_ID(bom_item_variant_edge) AS issue_edge_id,
      VERTEX_ID(variant_node) AS issue_vertex_id,
      VERTEX_ID(step_source_node) AS source_vertex_id,
      EDGE_ID(step_edge) AS edge_id,
      VERTEX_ID(step_destination_node) AS destination_vertex_id
    )
  )
ORDER BY
  bom_code,
  issue_type,
  issue_code;

--==============================================================================
--  Question 5: For a selected component revision, which BOMs and BOM items
--  are affected, and which other revisions of the same component are
--  available?
--
--  Expected result:
--    * Each row represents a traversal step in the affected-BOM path or the
--      other-revision path for the selected component revision.
--    * Other revisions are returned even when they are not used by a BOM.
--    * The result includes native identifiers for every vertex and edge in
--      the impact path, which can be used to visualize the revision impact.
--==============================================================================

PROMPT
PROMPT === Question 5: used component revisions with alternatives ===

COLUMN revision_id FORMAT 999999999
COLUMN part_number FORMAT A30
COLUMN revision_code FORMAT A15
COLUMN revision_status FORMAT A15
COLUMN revision_date FORMAT A12
COLUMN affected_bom_count FORMAT 999,999

SELECT
  revision.revision_id,
  component.part_number,
  revision.revision_code,
  revision.revision_status,
  revision.revision_date,
  COUNT(DISTINCT item.bom_id) AS affected_bom_count
FROM
  bom_component_revisions revision
  JOIN bom_components component
    ON component.component_id = revision.component_id
  JOIN bom_items item
    ON item.revision_id = revision.revision_id
WHERE
  EXISTS (
    SELECT
      1
    FROM
      bom_component_revisions other_revision
    WHERE
      other_revision.component_id = revision.component_id
      AND other_revision.revision_id <> revision.revision_id
  )
GROUP BY
  revision.revision_id,
  component.part_number,
  revision.revision_code,
  revision.revision_status,
  revision.revision_date
ORDER BY
  affected_bom_count DESC,
  component.part_number,
  revision.revision_code
FETCH FIRST 20 ROWS ONLY;

-- Replace the numeric literal 52 with a REVISION_ID returned above before
-- running this query in a graph visualization client. The client executes
-- this query independently and cannot supply SQLcl substitution-variable
-- values.

SELECT
  selected_part_number,
  selected_revision_code,
  bom_code,
  selected_bom_item_id,
  other_revision_code,
  other_revision_status,
  path_name,
  selected_revision_vertex_id,
  selected_bom_item_revision_edge_id,
  selected_bom_item_vertex_id,
  selected_bom_item_bom_edge_id,
  bom_header_vertex_id,
  component_vertex_id,
  selected_component_revision_edge_id,
  other_component_revision_edge_id,
  other_revision_vertex_id,
  source_vertex_id,
  edge_id,
  destination_vertex_id
FROM
  GRAPH_TABLE (
    bom_graph
    MATCH
      affected_bom_path = (selected_revision_node IS component_revision WHERE selected_revision_node.revision_id = 52)
      <-[selected_bom_item_revision_edge IS bom_item_revision]-
      (selected_bom_item_node IS bom_item)
      -[selected_bom_item_bom_edge IS bom_item_bom]->
      (header_node IS bom_header),
      other_revision_path = (selected_revision_node IS component_revision)
      -[selected_component_revision_edge IS component_revision]->
      (component_node IS component)
      <-[other_component_revision_edge IS component_revision]-
      (other_revision_node IS component_revision)
    WHERE
      NOT VERTEX_EQUAL(selected_revision_node, other_revision_node)
    ONE ROW PER STEP (
      step_source_node,
      step_edge,
      step_destination_node
    )
    IN (
      affected_bom_path,
      other_revision_path
    )
    COLUMNS (
      component_node.part_number AS selected_part_number,
      selected_revision_node.revision_code AS selected_revision_code,
      header_node.bom_code AS bom_code,
      selected_bom_item_node.bom_item_id AS selected_bom_item_id,
      other_revision_node.revision_code AS other_revision_code,
      other_revision_node.revision_status AS other_revision_status,
      PATH_NAME() AS path_name,
      VERTEX_ID(selected_revision_node) AS selected_revision_vertex_id,
      EDGE_ID(selected_bom_item_revision_edge) AS selected_bom_item_revision_edge_id,
      VERTEX_ID(selected_bom_item_node) AS selected_bom_item_vertex_id,
      EDGE_ID(selected_bom_item_bom_edge) AS selected_bom_item_bom_edge_id,
      VERTEX_ID(header_node) AS bom_header_vertex_id,
      VERTEX_ID(component_node) AS component_vertex_id,
      EDGE_ID(selected_component_revision_edge) AS selected_component_revision_edge_id,
      EDGE_ID(other_component_revision_edge) AS other_component_revision_edge_id,
      VERTEX_ID(other_revision_node) AS other_revision_vertex_id,
      VERTEX_ID(step_source_node) AS source_vertex_id,
      EDGE_ID(step_edge) AS edge_id,
      VERTEX_ID(step_destination_node) AS destination_vertex_id
    )
  )
ORDER BY
  bom_code,
  selected_bom_item_id,
  path_name,
  other_revision_code;

--==============================================================================
--  Question 6: Which components are structurally critical across the BOM
--  portfolio and therefore have the widest potential change impact?
--
--  Expected result:
--    * The 20 highest PageRank component vertices are selected from the full
--      BOM graph.
--    * Each row represents a BOM-use traversal step for one of those
--      components and includes its PageRank score and native graph IDs.
--
--  Prerequisite:
--    * EXECUTE on DBMS_OGA, plus graph query privileges.
--==============================================================================

PROMPT
PROMPT === Question 6: structurally critical components ===

COLUMN part_number FORMAT A30
COLUMN component_name FORMAT A60
COLUMN component_pagerank FORMAT 0.9999999999
COLUMN bom_code FORMAT A30

WITH
  component_ranks AS (
    SELECT
      component_id,
      part_number,
      component_name,
      component_pagerank
    FROM
      GRAPH_TABLE (
        DBMS_OGA.PAGERANK (
          bom_graph,
          PROPERTY(VERTEX OUTPUT component_pagerank),
          50,
          0.000001d,
          0.85d,
          FALSE
        )
        MATCH (component_node IS component)
        COLUMNS (
          component_node.component_id AS component_id,
          component_node.part_number AS part_number,
          component_node.component_name AS component_name,
          component_node.component_pagerank AS component_pagerank
        )
      )
  ),
  top_components AS (
    SELECT
      component_id,
      part_number,
      component_name,
      component_pagerank
    FROM
      component_ranks
    ORDER BY
      component_pagerank DESC,
      part_number
    FETCH FIRST 20 ROWS ONLY
  )
SELECT
  top_components.component_pagerank,
  top_components.part_number,
  top_components.component_name,
  graph_result.bom_code,
  graph_result.bom_header_vertex_id,
  graph_result.bom_item_bom_edge_id,
  graph_result.bom_item_vertex_id,
  graph_result.bom_item_component_edge_id,
  graph_result.component_vertex_id,
  graph_result.source_vertex_id,
  graph_result.edge_id,
  graph_result.destination_vertex_id
FROM
  GRAPH_TABLE (
    bom_graph
    MATCH
      (header_node IS bom_header)
      <-[bom_item_bom_edge IS bom_item_bom]-
      (bom_item_node IS bom_item)
      -[bom_item_component_edge IS bom_item_component]->
      (component_node IS component)
    ONE ROW PER STEP (
      step_source_node,
      step_edge,
      step_destination_node
    )
    COLUMNS (
      component_node.component_id AS component_id,
      header_node.bom_code AS bom_code,
      VERTEX_ID(header_node) AS bom_header_vertex_id,
      EDGE_ID(bom_item_bom_edge) AS bom_item_bom_edge_id,
      VERTEX_ID(bom_item_node) AS bom_item_vertex_id,
      EDGE_ID(bom_item_component_edge) AS bom_item_component_edge_id,
      VERTEX_ID(component_node) AS component_vertex_id,
      VERTEX_ID(step_source_node) AS source_vertex_id,
      EDGE_ID(step_edge) AS edge_id,
      VERTEX_ID(step_destination_node) AS destination_vertex_id
    )
  ) graph_result
  JOIN top_components
    ON top_components.component_id = graph_result.component_id
ORDER BY
  top_components.component_pagerank DESC,
  top_components.part_number,
  graph_result.bom_code;

--==============================================================================
--  Question 7: Which BOMs, assemblies, components, and revisions form
--  disconnected islands outside the main product structure?
--
--  Expected result:
--    * Each graph edge is returned with the weak-component ID of both
--      endpoint vertices.
--    * Equal WCC_GROUP_ID values identify vertices in the same undirected
--      connected component and can be used to color the visualization.
--
--  Prerequisite:
--    * EXECUTE on DBMS_OGA, plus graph query privileges.
--==============================================================================

PROMPT
PROMPT === Question 7: disconnected BOM graph islands ===

COLUMN source_wcc_group_id FORMAT 999,999,999
COLUMN destination_wcc_group_id FORMAT 999,999,999

SELECT
  source_wcc_group_id,
  destination_wcc_group_id,
  source_vertex_id,
  edge_id,
  destination_vertex_id,
  step_source_vertex_id,
  step_edge_id,
  step_destination_vertex_id
FROM
  GRAPH_TABLE (
    DBMS_OGA.WCC (
      bom_graph,
      PROPERTY(VERTEX OUTPUT wcc_group_id)
    )
    MATCH
      (source_node)
      -[graph_edge]->
      (destination_node)
    ONE ROW PER STEP (
      step_source_node,
      step_edge,
      step_destination_node
    )
    COLUMNS (
      source_node.wcc_group_id AS source_wcc_group_id,
      destination_node.wcc_group_id AS destination_wcc_group_id,
      VERTEX_ID(source_node) AS source_vertex_id,
      EDGE_ID(graph_edge) AS edge_id,
      VERTEX_ID(destination_node) AS destination_vertex_id,
      VERTEX_ID(step_source_node) AS step_source_vertex_id,
      EDGE_ID(step_edge) AS step_edge_id,
      VERTEX_ID(step_destination_node) AS step_destination_vertex_id
    )
  );
