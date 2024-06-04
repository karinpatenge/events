----------------------------
-- Airports in Hamburg
----------------------------

SELECT a.iata, a.name
FROM airports a, cities c
WHERE c.city='Hamburg'
  AND a.city_id=c.id
  AND a.icao IS NOT NULL;

-- Using GRAPH_TABLE function
SELECT * FROM GRAPH_TABLE(
  flight_graph
  MATCH (a IS airport) -> (c IS city WHERE c.city='Hamburg')
  WHERE a.icao IS NOT NULL AND c.country = 'Germany'
  COLUMNS (a.iata, a.name)
);

-------------------------------------------------
-- Airlines operating flights between HAM and LHR
-------------------------------------------------

SELECT * FROM GRAPH_TABLE(
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') -[r IS route]-> (d IS airport WHERE d.iata='LHR')
  COLUMNS (r.airline_name AS airline)
)
ORDER BY 1;

--------------------------------------------------------------------
-- Airlines operating flights between HAM and LHR in both directions
--------------------------------------------------------------------

SELECT * FROM GRAPH_TABLE(
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') -[r IS route]- (d IS airport WHERE d.iata='LHR')
  COLUMNS (a.iata AS src_airport, r.airline_name AS airline, d.iata AS dst_airport)
)
ORDER BY src_airport, airline, dst_airport;

--------------------------------------------------------------
-- Number of destinations I can reach FROM HAM with 1 stopover
--------------------------------------------------------------

SELECT COUNT(DISTINCT(iata)) AS no_of_reachable_airports FROM GRAPH_TABLE(
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') -[r IS route]->{2} (d IS airport)
  WHERE a.iata <> d.iata
  COLUMNS (d.iata)
);

----------------------------------------------------------------------------------
-- How many cities (instead of airports) can be reached with 1 stopover
----------------------------------------------------------------------------------

SELECT COUNT(DISTINCT(city)) AS no_of_reachable_cities FROM GRAPH_TABLE(
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') -[r IS route]->{2} (d IS airport) -> (c IS city)
  WHERE a.iata <> d.iata
  COLUMNS (c.city)
);

-------------------------------------------------------------------------------------
-- How many cities (instead of airports) can be reached with a maximum of 3 stopovers
-------------------------------------------------------------------------------------

SELECT COUNT(DISTINCT(city)) AS no_of_reachable_cities FROM GRAPH_TABLE(
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') -[r IS route]->{2} (d IS airport) -> (c IS city)
  WHERE a.iata <> d.iata
  COLUMNS (c.city)
);

-----------------------------------------------------------
-- How many options do I have to get to Burketown/Australia
-- with up to three stopovers, ie. up to 4 flight segments?
-----------------------------------------------------------

SELECT COUNT(DISTINCT(city)) AS no_of_reachable_cities FROM GRAPH_TABLE(
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') -[r IS route]->{1,4} (d IS airport WHERE d.iata='BUC') -> (c IS city)
  COLUMNS (c.city)
);

-----------------------------------------------------------
-- How many options do I have to get to Burketown/Australia
-- with up to four stopovers, ie. up to 5 flight segments?
-----------------------------------------------------------

SELECT COUNT(DISTINCT(city)) AS no_of_reachable_cities FROM GRAPH_TABLE(
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') -[r IS route]->{1,5} (d IS airport WHERE d.iata='BUC') -> (c IS city)
  WHERE a.iata <> d.iata
  COLUMNS (c.city)
);

------------------------------------------------------------------------
-- Which airports do I have stopovers on the way to Burketown/Australia?
------------------------------------------------------------------------

-- Max 4 stopovers
SELECT DISTINCT * FROM GRAPH_TABLE (
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') (-[r IS route]->(stopover IS airport)){1,4}->(d IS airport WHERE d.iata='BUC')
  COLUMNS (
    a.iata AS src_airport,
    LISTAGG(stopover.iata, ',') AS list_of_stopover_airports,
    d.iata AS dst_airport,
    COUNT(r.id)+1 AS flight_segments)
);

-- Max 5 stopovers
SELECT DISTINCT * FROM GRAPH_TABLE (
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') (-[r IS route]->(stopover IS airport)){1,5}->(d IS airport WHERE d.iata='BUC')
  COLUMNS (
    a.iata AS src_airport,
    LISTAGG(stopover.iata, ',') AS list_of_stopover_airports,
    d.iata AS dst_airport,
    COUNT(r.id)+1 AS flight_segments)
);

-- Alternative query
SELECT routing
FROM GRAPH_TABLE(
  flight_graph
  MATCH (a IS airport WHERE a.iata='HAM') (-[r IS route]->(stopover IS airport)){1,5} (d IS airport WHERE d.iata='BUC')
  COLUMNS (LISTAGG(stopover.iata, '->') AS routing)
);