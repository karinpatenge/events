SELECT *
FROM GRAPH_TABLE (
  aaa_students_graph
  MATCH (v1)-[e]->(v2)
  COLUMNS (
    vertex_id(v1) AS v1_node_id,
    edge_id(e) AS e_edge_id,
    vertex_id(v2) AS v2_node_id
  )
)