----------------------------------------
-- Query the FLIGHT_GRAPH using GraphViz
----------------------------------------

SELECT id_a, id_e, id_b FROM GRAPH_TABLE(
  flight_graph
  MATCH (a)-[e]->(b)
  COLUMNS (VERTEX_ID(a) AS id_a, EDGE_ID(e) AS id_e, VERTEX_ID(b) AS id_b)
)
FETCH FIRST 10 ROWS ONLY;

SELECT *
FROM GRAPH_TABLE (
  flight_graph
  MATCH (c1 IS city WHERE c1.city = 'Paris' AND c1.country = 'France') <-[l1 IS located_in]- (a1)
         -[r IS route]-> (a2) -[l2 IS located_in]->
        (c2 IS city WHERE c2.city = 'London' AND c2.country = 'United Kingdom')
  COLUMNS (
    vertex_id(c1) AS id_c1,
    vertex_id(c2) AS id_c2,
    vertex_id(a1) AS id_a1,
    vertex_id(a2) AS id_a2,
    edge_id(l1) AS id_l1,
    edge_id(l2) AS id_l2,
    edge_id(r) AS id_r)
) FETCH FIRST 100 ROWS ONLY;