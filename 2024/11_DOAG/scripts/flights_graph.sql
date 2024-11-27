------------------------------
-- Create an OpenFlights graph
------------------------------

DROP PROPERTY GRAPH IF EXISTS flights_graph;

CREATE PROPERTY GRAPH flights_graph
  VERTEX TABLES (
    airports
      KEY (id)
      LABEL airport
      PROPERTIES ALL COLUMNS,
    cities
      KEY (id)
      LABEL city
      PROPERTIES (city, country)
  )
  EDGE TABLES (
    routes
      KEY (id)
      SOURCE KEY (orig_airport_id) REFERENCES airports (id)
      DESTINATION KEY (dest_airport_id) REFERENCES airports (id)
      LABEL route
      PROPERTIES ALL COLUMNS,
    airports AS located_in
      SOURCE KEY (id) REFERENCES airports (id)
      DESTINATION KEY (city_id) REFERENCES cities (id)
      LABEL located_in
      NO PROPERTIES
   );

------------------------------
-- Metadata in data dictionary
------------------------------

select * from user_property_graphs order by graph_name;
select * from user_pg_elements where graph_name='FLIGHTS_GRAPH';
select * from user_pg_label_properties where graph_name='FLIGHTS_GRAPH';

--------------------------------------------------------
-- Sample SQL/PGQ queries using the OpenFlights data set
--------------------------------------------------------

-- Airports in Nuernberg

SELECT * FROM GRAPH_TABLE(flights_graph
  MATCH (a IS airport) -[]-> (c IS city)
  WHERE c.city='Nuernberg' AND c.country='Germany'
  COLUMNS (a.iata, a.name)
);

-- Airlines operating flights between NUE AND TXL

SELECT * FROM GRAPH_TABLE(flights_graph
  MATCH (a IS airport) -[r IS route]-> (d IS airport)
  WHERE a.iata='NUE' AND d.iata='TXL'
  COLUMNS (r.airline AS airline)
) ORDER BY airline;

-- Airlines operating flights between NUE AND TXL in both directions

SELECT * FROM GRAPH_TABLE(flights_graph
  MATCH (a IS airport) -[r IS route]- (d IS airport)
  WHERE a.iata='NUE' AND d.iata='TXL'
  COLUMNS (r.airline AS airline)
) ORDER BY airline;

-- Number of different destinations can be reached from NUE with 1 stopover

SELECT COUNT(DISTINCT(iata)) FROM GRAPH_TABLE(flights_graph
  MATCH (a IS airport) -[r IS route]->{2} (d IS airport)
  WHERE  a.iata='NUE' AND a.iata <> d.iata
  COLUMNS (d.iata)
);

-- How many different cities can be reached from NUE with 1 stopover

SELECT COUNT(DISTINCT(city)) FROM GRAPH_TABLE(flights_graph
  MATCH (a IS airport) -[r IS route]->{2} (d IS airport) -> (c IS city)
  WHERE  a.iata='NUE' AND a.iata <> d.iata
  COLUMNS (c.city)
);

-- How many options exist to get to Burketown with up to
-- three stopovers, ie. up to 4 flight segments?

SELECT count(*) FROM GRAPH_TABLE(flights_graph
  MATCH (a IS airport) -[r IS route]->{1,4} (d IS airport)
  WHERE a.iata='NUE' AND d.iata='BUC'
  COLUMNS (d.iata)
);

-- How many options exist to get to Burketown with up to
-- six stopovers, ie. up to 7 flight segments?

SELECT count(*) FROM GRAPH_TABLE(flights_graph
  MATCH (a IS airport) -[r IS route]->{1,6} (d IS airport)
  WHERE a.iata='NUE' AND d.iata='BUC'
  COLUMNS (d.iata)
);

-- Compute the total distance of the routes

SELECT DISTINCT * FROM GRAPH_TABLE (flights_graph
  MATCH (a IS airport) (-[r]->(i IS airport)){1,6} (d IS airport)
  WHERE a.iata='NUE' AND d.iata='BUC'
  COLUMNS (
    a.iata AS src_airport,
    sum(r.dIStance) AS dIStance,
    d.iata AS dst_airport,
    COUNT(r.id) AS flight_segments)
) ORDER BY distance;

-- Find all airports along the routes

SELECT DISTINCT * FROM GRAPH_TABLE (flights_graph
  MATCH (a IS airport) (-[r]->(i IS airport)){1,6} (d IS airport)
  WHERE a.iata='NUE' AND d.iata='BUC'
  COLUMNS (
    a.iata AS src_airport,
    LISTAGG(i.iata, ' -> ') AS list_of_airports,
    d.iata AS dst_airport,
    COUNT(r.id)+1 AS flight_segments)
);

