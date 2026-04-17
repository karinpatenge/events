SELECT *
FROM GRAPH_TABLE (
  aaa_openflights_plus_graph
  MATCH (a IS airport WHERE a.iata='LJU') -[r IS route]-> {1,3}(d IS airport WHERE d.iata='TXL')
  ONE ROW PER STEP (v1, e, v2)
  COLUMNS (
    vertex_id(v1) AS src,
    edge_id(e) AS route,
    e.airline AS airline,
    vertex_id(v2) AS dst
  )
)
ORDER BY airline