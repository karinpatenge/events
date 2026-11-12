/*********************************************
 * Create table for tram stations in Zagreb
 *
 * Author: Karin Patenge
 * Date: October 2026
 *********************************************/

--
-- Documentation: https://docs.oracle.com/en/database/oracle/oracle-database/26/spatl/
-- Data set: ./insert_tram_stations.sql (© OpenStreetMap contributors, ODbL)
--
-- 26ai features used:
--   * CREATE TABLE IF NOT EXISTS
--   * DEFAULT ON NULL
--   * Annotations on table and columns (usable as metadata by Select AI)
--   * No manual insert into USER_SDO_GEOM_METADATA:
--     the metadata is created automatically with the spatial index.
--     The index needs at least one non-NULL geometry, so it is created
--     at the end of insert_tram_stations.sql
--
-- File encoding: UTF-8 (Croatian diacritics in annotations)
--

-- If needed, drop the table
DROP TABLE IF EXISTS tram_stations PURGE;

-- Create the table
CREATE TABLE IF NOT EXISTS tram_stations (
  station_code          VARCHAR2(1)
                        CONSTRAINT tram_stations_pk PRIMARY KEY
                        ANNOTATIONS (Display 'Code', Description 'Station code A to D as shown on the hook slide'),
  station_name          VARCHAR2(100)
                        NOT NULL
                        ANNOTATIONS (Display 'Station', Description 'Official ZET stop name'),
  tram_line             VARCHAR2(4)
                        DEFAULT ON NULL '6'
                        NOT NULL
                        ANNOTATIONS (Display 'Tram line', Description 'ZET tram line used in the hook'),
  site_note             VARCHAR2(200)
                        ANNOTATIONS (Display 'Site', Description 'Short description of the surroundings of the stop'),
  geom                  SDO_GEOMETRY
                        NOT NULL
                        ANNOTATIONS (Display 'Station location', Description 'Midpoint between both stop positions, WGS84 lon/lat (SRID 4326)'),
  geom_to_sopot         SDO_GEOMETRY
                        ANNOTATIONS (Display 'Stop towards Sopot', Description 'Stop position of trams heading to Sopot, WGS84 lon/lat (SRID 4326)'),
  geom_to_crnomerec     SDO_GEOMETRY
                        ANNOTATIONS (Display 'Stop towards Črnomerec', Description 'Stop position of trams heading to Črnomerec, WGS84 lon/lat (SRID 4326)'),
  osm_node_to_sopot     NUMBER(12)
                        ANNOTATIONS (Display 'OSM node towards Sopot', Description 'OpenStreetMap node ID of the stop position towards Sopot'),
  osm_node_to_crnomerec NUMBER(12)
                        ANNOTATIONS (Display 'OSM node towards Črnomerec', Description 'OpenStreetMap node ID of the stop position towards Črnomerec'),
  gtfs_stop_id          VARCHAR2(30)
                        ANNOTATIONS (Display 'GTFS stop ID', Description 'ZET GTFS stop_id, to be filled after loading stops.txt'),
  data_source           VARCHAR2(200)
                        DEFAULT ON NULL 'OpenStreetMap contributors (ODbL), Overpass API, 2026-10-06'
                        NOT NULL
                        ANNOTATIONS (Display 'Source', Description 'Origin and retrieval date of the coordinates')
)
ANNOTATIONS (
  Display 'Tram stations',
  Description 'Tram stations A to D on ZET tram line 6 (Črnomerec - Sopot) in Zagreb, used in the Spatial Meets AI demo hook'
);

-- Check the annotations
SELECT
  object_name,
  column_name,
  annotation_name,
  annotation_value
FROM
  USER_ANNOTATIONS_USAGE
WHERE
  object_name = 'TRAM_STATIONS'
ORDER BY
  column_name NULLS FIRST,
  annotation_name;
