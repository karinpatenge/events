SELECT *
FROM
  GRAPH_TABLE (
    aaa_students_graph
    MATCH (p1 IS person) -[f IS is_friend_of]-> (p2 IS person)-[e IS studied|studied_at]-> (v)
    WHERE v.name = 'Mathematics' or v.name = 'University of Maribor'
    COLUMNS (
      p1.name AS friend_name,
      p2.name AS person_name,
      vertex_id(p1) AS p1_node_id,
      edge_id(f) AS f_edge_id,
      vertex_id(p2) AS p2_node_id,
      edge_id(e) AS e_edge_id,
      vertex_id(v) AS v_node_id
    )
  )
ORDER BY
  person_name,
  friend_name