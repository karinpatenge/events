-----------------------------------------------
-- Extend graph with table of train connections
-----------------------------------------------

--------------------------------------
-- Clean up existing train connections
--------------------------------------

TRUNCATE TABLE train_connections DROP STORAGE;

------------------------------
-- Drop the graph if it exists
------------------------------

DROP PROPERTY GRAPH IF EXISTS flight_ext_graph;

-------------------------------------------------------------
-- Create the extended graph containing train connections too
-------------------------------------------------------------

CREATE PROPERTY GRAPH flight_ext_graph
  VERTEX TABLES (
    airports
      KEY (id)
      LABEL airport
      PROPERTIES (name, iata, icao, airport_type, altitude),
    cities
      KEY (id)
      LABEL city
      PROPERTIES (city, country)
  )
  EDGE TABLES (
    airports AS airports_in_cities
      KEY (id)
      SOURCE KEY(id) REFERENCES airports (id)
      DESTINATION KEY(city_id) REFERENCES cities (id)
      LABEL located_in
      NO PROPERTIES,
    routes
      KEY (id)
      SOURCE KEY(src_airport_id) REFERENCES airports (id)
      DESTINATION KEY(dest_airport_id) REFERENCES airports (id)
      LABEL ROUTE
      PROPERTIES (airline_name, distance_in_km),
    train_connections AS tc
      KEY (id)
      SOURCE KEY(orig_airport_id) REFERENCES airports (id)
      DESTINATION KEY(dest_airport_id) REFERENCES airports (id)
      LABEL train_connection
       PROPERTIES (tc.details.Operator.string() AS operator, distance)
  );

------------------------------
-- Graph Metadata
------------------------------

SELECT * FROM user_property_graphs
ORDER BY 1;

SELECT * FROM user_pg_elements
WHERE graph_name='FLIGHT_EXT_GRAPH';

SELECT * FROM user_pg_label_properties
WHERE graph_name='FLIGHT_EXT_GRAPH';

-------------------------------------------------------------
-- Find all train destinations and their operators from Paris
-------------------------------------------------------------

SELECT * FROM GRAPH_TABLE(
  flight_ext_graph
  MATCH (a IS airport where a.iata='PAR') -[r IS train_connection]-> (d IS airport)
  COLUMNS (d.iata, d.name, r.operator)
);

----------------------------
-- Add new train connections
----------------------------

INSERT INTO train_connections VALUES (
  987,
  (SELECT id FROM airports WHERE iata='PAR'),
  (SELECT id FROM airports WHERE iata='LON'),
  219,
  '{"Operator":"Eurostar", "Stops":0, "Load":"Passengers"}');
INSERT INTO train_connections VALUES (
  988,
  (SELECT id FROM airports WHERE iata='LON'),
  (SELECT id FROM airports WHERE iata='PAR'),
  219,
  '{"Operator":"Eurostar", "Stops":0, "Load":"Passengers"}');
INSERT INTO train_connections VALUES (
  1247,
  (SELECT id FROM airports WHERE iata='PAR'),
  (SELECT id FROM airports WHERE iata='LON'),
  219,
  '{"Operator":"LeShuttle", "Stops":0, "Load":["Passengers", "Vehicles"]}');
INSERT INTO train_connections VALUES (
  1248,
  (SELECT id FROM airports WHERE iata='LON'),
  (SELECT id FROM airports WHERE iata='PAR'),
  219,
  '{"Operator":"LeShuttle", "Stops":0, "Load":["Passengers", "Vehicles"]}');

COMMIT;

-----------------------------------------------------------------
-- Now find all train destinations and their operators from Paris
-----------------------------------------------------------------

SELECT * FROM GRAPH_TABLE(
  flight_ext_graph
  MATCH (a IS airport where a.iata='PAR') -[r IS train_connection]-> (d IS airport)
  COLUMNS (d.iata, d.name, r.operator)
);

-------------------------------------------------------------------
-- How many different paths connect Paris and London (only flights)
-------------------------------------------------------------------

SELECT * FROM GRAPH_TABLE(
  flight_ext_graph
  MATCH (c1 IS city WHERE c1.city = 'Paris' AND c1.country = 'France') <-[l1 IS located_in]- (a1)
         -[r IS route]-> (a2) -[l2 IS located_in]->
        (c2 IS city WHERE c2.city = 'London' AND c2.country = 'United Kingdom')
  COLUMNS (a1.iata AS src_airport, r.airline_name AS airline, a2.iata AS dst_airport)
)
ORDER BY src_airport, dst_airport, airline;

-------------------------------------------------------------------------
-- How many different paths connect Paris and London (flights and trains)
-------------------------------------------------------------------------

SELECT * FROM GRAPH_TABLE(
  flight_ext_graph
  MATCH (c1 IS city WHERE c1.city = 'Paris' AND c1.country = 'France') <-[l1 IS located_in]- (a1)
         -[r IS route | train_connection]-> (a2) -[l2 IS located_in]->
        (c2 IS city WHERE c2.city = 'London' AND c2.country = 'United Kingdom')
  COLUMNS (a1.iata AS src_airport, r.airline_name AS airline, r.operator, a2.iata AS dst_airport)
);
