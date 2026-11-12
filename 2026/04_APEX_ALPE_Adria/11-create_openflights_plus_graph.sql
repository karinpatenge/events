-- Clean up the graph if it already exists
DROP PROPERTY GRAPH IF EXISTS aaa_openflights_plus_graph;

-- Create the property graph based on the OpenFlights dataset with additional train connections data (JSON)
CREATE PROPERTY GRAPH IF NOT EXISTS aaa_openflights_plus_graph
  VERTEX TABLES (
    airports
      KEY ( id )
      LABEL airport PROPERTIES ARE ALL COLUMNS,
    cities
      KEY ( id )
      LABEL city PROPERTIES ( id, country, city )
  )
  EDGE TABLES (
    airports AS LOCATED_IN KEY ( id )
      SOURCE KEY ( id ) REFERENCES airports (id)
      DESTINATION KEY ( city_id ) REFERENCES cities (id)
      LABEL located_in NO PROPERTIES,
    routes KEY ( id )
      SOURCE KEY ( orig_airport_id ) REFERENCES airports ( id )
      DESTINATION KEY ( dest_airport_id ) REFERENCES airports ( id )
      LABEL route PROPERTIES ARE ALL COLUMNS,
    train_connections AS TC
      SOURCE KEY ( orig_airport_id ) REFERENCES airports ( id )
      DESTINATION KEY ( dest_airport_id ) REFERENCES airports ( id )
      LABEL train_connection PROPERTIES (
        distance,
        JSON_VALUE (details FORMAT OSON , '$.Operator.string()' RETURNING VARCHAR2(4000) NULL ON ERROR TYPE(LAX) ) AS operator
      )
  )

-- Remark:
-- Autonomous JSON Database under the covers: OSON format -> https://blogs.oracle.com/database/autonomous-json-database-under-the-covers-oson-format



