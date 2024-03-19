----------------------------------------
-- Drop existing graph
----------------------------------------
DROP PROPERTY GRAPH IF EXISTS flight_graph;

----------------------------------------
-- Create existing graph
----------------------------------------
CREATE PROPERTY GRAPH flight_graph
  VERTEX TABLES (
    airports AS airports
      KEY ( id )
      LABEL airport
      PROPERTIES ARE ALL COLUMNS,
    cities AS cities
      KEY ( id )
      LABEL city
      PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    routes AS routes
      KEY ( id )
      SOURCE KEY ( src_airport_id ) REFERENCES airports ( id )
      DESTINATION KEY ( dest_airport_id ) REFERENCES airports ( id )
      LABEL route
      PROPERTIES ARE ALL COLUMNS,
    airports AS airports_in_cities
      SOURCE KEY ( id ) REFERENCES airports ( id )
      DESTINATION KEY ( city_id ) REFERENCES cities ( id )
      LABEL located_in
      NO PROPERTIES
  );
