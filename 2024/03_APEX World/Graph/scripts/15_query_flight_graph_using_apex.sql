---------------------------------
-- Query the FLIGHT_GRAPH in APEX
---------------------------------
SELECT cust_sqlgraph_json('
  SELECT * FROM GRAPH_TABLE(
    flight_ext_graph
    MATCH (c1 IS city WHERE c1.city = ''Paris'' AND c1.country = ''France'') <-[l1 IS located_in]- (a1)
           -[r IS route]-> (a2) -[l2 IS located_in]->
          (c2 IS city WHERE c2.city = ''London'' AND c2.country = ''United Kingdom'')
    COLUMNS (
      VERTEX_ID(c1) AS src_city,
      EDGE_ID(l1) AS in1,
      VERTEX_ID(a1) AS src_airport,
      EDGE_ID(r) AS connection,
      VERTEX_ID(a2) AS dst_airport,
      EDGE_ID(l2) AS in2,
      VERTEX_ID(c2) AS dst_city
    )
  )
',
:page_start,
:page_size
) AS result FROM DUAL