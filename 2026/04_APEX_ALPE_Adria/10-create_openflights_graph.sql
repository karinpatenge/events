-- Clean up the graph if it already exists
DROP PROPERTY GRAPH IF EXISTS aaa_openflights_graph;

-- Create the property graph based on the OpenFlights dataset
CREATE PROPERTY GRAPH IF NOT EXISTS aaa_openflights_graph
  VERTEX TABLES (
    openflights_airports AS airports
      KEY ( id )
      LABEL airport
      PROPERTIES ARE ALL COLUMNS,
    openflights_cities AS cities
      KEY ( id )
      LABEL city
      PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    openflights_routes AS routes
      SOURCE KEY ( src_airport_id ) REFERENCES airports (id)
      DESTINATION KEY ( dest_airport_id ) REFERENCES airports (id)
      LABEL route
      PROPERTIES ARE ALL COLUMNS,
    openflights_airports AS airports_in_cities
      SOURCE KEY ( id ) REFERENCES airports (id)
      DESTINATION KEY ( city_id ) REFERENCES cities (id)
      LABEL located_in
      NO PROPERTIES
  );

