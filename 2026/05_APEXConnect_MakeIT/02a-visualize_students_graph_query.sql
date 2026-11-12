-- Query the graph:
-- Who (p1) is friend (f) of a person (p2) that studied (e) either mathematics (v) or studied at (e) the University of Hannover (v)?
-- Return the names of the persons that match the criteria.
SELECT *
FROM
  GRAPH_TABLE (
    students_graph
    MATCH (p1 IS person) -[f IS is_friend_of]-> (p2 IS person)-[e IS studied|studied_at]-> (v)
    WHERE v.name = 'Mathematics' OR v.name = 'University of Hannover'
    COLUMNS (
      p1.name AS person_name,
      vertex_id(p1) AS p1_node_id,
      edge_id(f) AS f_edge_id,
      vertex_id(p2) AS p2_node_id,
      edge_id(e) AS e_edge_id,
      vertex_id(v) AS v_node_id
    )
  )
ORDER BY
  person_name