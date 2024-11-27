-----------------------------------------------
-- Extend graph with table of train connections
-----------------------------------------------

TRUNCATE TABLE train_connections DROP STORAGE;

-- Add new train connections using SQL

INSERT INTO TRAIN_CONNECTIONS VALUES (987,
   (select id from airports where iata='PAR'),
   (select id from airports where iata='LON'),
   219,
   '{"Operator":"Eurostar", "Stops":0, "Load":"Passengers"}');
INSERT INTO TRAIN_CONNECTIONS VALUES (988,
   (select id from airports where iata='LON'),
   (select id from airports where iata='PAR'),
   219,
   '{"Operator":"Eurostar", "Stops":0, "Load":"Passengers"}');
INSERT INTO TRAIN_CONNECTIONS VALUES (1247,
   (select id from airports where iata='PAR'),
   (select id from airports where iata='LON'),
   219,
   '{"Operator":"LeShuttle", "Stops":0, "Load":["Passengers", "Vehicles"]}');
INSERT INTO TRAIN_CONNECTIONS VALUES (1248,
   (select id from airports where iata='LON'),
   (select id from airports where iata='PAR'),
   219,
   '{"Operator":"LeShuttle", "Stops":0, "Load":["Passengers", "Vehicles"]}');

COMMIT;

SELECT * FROM train_connections;

----------------------------

DROP PROPERTY GRAPH IF EXISTS flights_plus_graph;

CREATE OR REPLACE PROPERTY GRAPH flights_plus_graph
    VERTEX TABLES (
        airports
            KEY (id)
            LABEL airport
            PROPERTIES (name, iata),
        CITIES
            KEY (id)
            LABEL city
            PROPERTIES ALL COLUMNS
    )
    EDGE TABLES (
        airports AS located_in
            KEY (id)
            SOURCE KEY(id) REFERENCES airports (id)
            DESTINATION KEY(city_id) REFERENCES cities (id)
            LABEL located_in
            NO PROPERTIES,
        routes
            KEY (ID)
            SOURCE KEY(ORIG_AIRPORT_ID) REFERENCES AIRPORTS (ID)
            DESTINATION KEY(DEST_AIRPORT_ID) REFERENCES AIRPORTS (ID)
            LABEL route
            PROPERTIES ALL COLUMNS,
        train_connections AS tc
            KEY (ID)
            SOURCE KEY(orig_airport_id) REFERENCES airports (id)
            DESTINATION KEY(dest_airport_id) REFERENCES airports (id)
            LABEL train_connection
            PROPERTIES (tc.details.Operator.string() as operator, distance)
    );

------------------------------
-- Metadata in data dictionary
------------------------------

select * from user_property_graphs order by graph_name;
select * from user_pg_elements where graph_name='FLIGHTS_PLUS_GRAPH';
select * from user_pg_label_properties where graph_name='FLIGHTS_PLUS_GRAPH';

-----------------------------------------------------------------
-- Sample SQL/PGQ queries using the extended OpenFlights data set
-----------------------------------------------------------------

-- Find all train destinations and their operators from Paris

SELECT * FROM GRAPH_TABLE(flights_plus_graph
    MATCH (a IS airport WHERE a.iata='PAR') -[r IS train_connection]-> (d IS airport)
    COLUMNS (d.iata, d.name, r.operator)
);

-- Now find all train destinations and their operators from Paris (different syntax)

SELECT * FROM GRAPH_TABLE(flights_plus_graph
    MATCH (a IS airport) -[r IS train_connection]-> (d IS airport)
    WHERE a.iata='PAR'
    COLUMNS (d.iata, d.name, r.operator)
);

-- How many routes connect Paris and London (only flights)

SELECT COUNT(*) FROM GRAPH_TABLE(flights_plus_graph
    MATCH (c1 IS city) <-[l1 IS located_in]- (a1)
          -[r IS route]-> (a2) -[l2 IS located_in]-> (c2 IS city)
    WHERE c1.city = 'Paris' AND c1.country = 'France' AND c2.city = 'London' AND c2.country = 'United Kingdom'
    COLUMNS (a1.iata AS airport1, r.airline AS airline, a2.iata AS airport2)
) ORDER BY airline;

-- Which routes connect Paris and London (flights and trains)

SELECT DISTINCT * FROM GRAPH_TABLE(flights_plus_graph
    MATCH (c1 IS city) <-[l1 IS located_in]- (a1)
          -[r IS route | train_connection]-> (a2) -[l2 IS located_in]-> (c2 IS city )
    WHERE c1.city = 'Paris' AND c1.country = 'France' AND c2.city = 'London' AND c2.country = 'United Kingdom'
    COLUMNS (a1.iata AS airport1, r.airline AS airline, r.operator AS operator, a2.iata AS airport2)
) ORDER BY operator, airline;
