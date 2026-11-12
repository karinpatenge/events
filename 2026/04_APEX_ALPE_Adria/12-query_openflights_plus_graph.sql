-- Show the entire graph
SELECT *
FROM GRAPH_TABLE (
  aaa_openflights_plus_graph
  MATCH (v1) -[e1]-> (v2) -[e2 IS located_in]-> (v3)
  COLUMNS (
    vertex_id(v1) AS src,
    edge_id(e1) AS route,
    vertex_id(v2) AS dst,
    edge_id(e2) AS located_in,
    vertex_id(v3) AS city)
);

-- Show all train connections between airports located in London and Paris
SELECT *
FROM GRAPH_TABLE (
  aaa_openflights_plus_graph
  MATCH (v1 IS city WHERE v1.city='London') <-[e1]- (v2 IS airport) -[e2 IS train_connection]-> (v3 IS airport) -[e3 IS located_in]-> (v4 IS city WHERE v4.city='Paris')
  COLUMNS (
    vertex_id(v1) AS node_v1,
    edge_id(e1) AS edge_e1,
    vertex_id(v2) AS node_v2,
    edge_id(e2) AS edge_e2,
    vertex_id(v3) AS node_v3,
    edge_id(e3) AS edge_e3,
    vertex_id(v4) AS node_v4
  )
);

-- How can I travel from London Heathrow Airport (LHR) to Paris?
SELECT *
FROM GRAPH_TABLE (
  aaa_openflights_plus_graph
  MATCH (a1 IS airport WHERE a1.iata='LHR') -[e1]-> (a2 IS airport) -[e2]-> (c IS city WHERE c.city='Paris')
  COLUMNS (
    vertex_id(a1) AS node_a,
    edge_id(e1) AS edge_e1,
    vertex_id(a2) AS node_b,
    edge_id(e2) AS edge_e2,
    vertex_id(c) AS node_c,
    a1.iata AS iata_a1,
    a2.iata AS iata_a2,
    c.city as city
  )
);

-- Which airports are located in Ljubljana, Slovenia?
SELECT *
FROM GRAPH_TABLE (
  aaa_openflights_plus_graph
  MATCH (a IS airport) -[e]-> (c IS city)
  WHERE c.city='Ljubljana' AND c.country='Slovenia'
  COLUMNS (
    vertex_id(a) AS airport,
    edge_id(e) AS located_in,
    vertex_id(c) AS city,
    a.iata,
    a.name
  )
);

-- Show me all flights from Ljubljana (LJU) to Berlin (TXL) with 1 up to 3 flight segments
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
ORDER BY airline;

-- Which airports are connected to Ljubljana (LJU) by 2 flight segments (i.e. 1 stopover)?
SELECT COUNT(DISTINCT(iata))
FROM GRAPH_TABLE (
  aaa_openflights_plus_graph
  MATCH (a IS airport) -[r is route]->{2} (d IS airport)
  WHERE  a.iata='LJU' AND a.iata <> d.iata
  COLUMNS (d.iata)
);

-- Show me the connections from Ljubljana (LJU) to other airports with 1 or 2 stopovers having flight segment distances between 1000 and 2000.
SELECT DISTINCT *
FROM GRAPH_TABLE (
  aaa_openflights_plus_graph
  MATCH (a IS airport) -[r IS route]->{1,2} (d IS airport)
  WHERE a.iata='LJU'
  ONE ROW PER STEP (v1, k, v2)
  COLUMNS (
    v1.iata AS iata1,
    v2.iata AS iata2,
    k.distance AS distance,
    k.airline AS airline
  )
)
WHERE
  distance > 1000 AND distance < 2000
ORDER BY
  iata1,
  iata2,
  distance;