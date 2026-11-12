/*********************************************
 * Insert the tram stations used in the
 * hook "3 pm · July · Tram 6"
 *
 * Author: Karin Patenge
 * Date: October 2026
 *********************************************/

--
-- Documentation: https://docs.oracle.com/en/database/oracle/oracle-database/26/spatl/
-- Data set: OpenStreetMap stop positions of ZET tram line 6
--           (relations 147093 Črnomerec => Sopot, 2183640 Sopot => Črnomerec),
--           retrieved via Overpass API on 2026-10-06. © OpenStreetMap contributors, ODbL
-- Prerequisite: ./create_table_tram_stations.sql
--
-- 26ai features used:
--   * Multi-row INSERT with a table value constructor
--   * SDO_GEOMETRY(longitude, latitude) constructor (SDO_GTYPE 2001, SDO_SRID 4326)
--   * Predefined constants SDO_POINT2D and SDO_LONLAT
--   * Automatic creation of USER_SDO_GEOM_METADATA with the spatial index
--   * CREATE INDEX IF NOT EXISTS
--
-- File encoding: UTF-8 (Croatian diacritics)
--

-- Insert all stations in one statement
-- tram_line and data_source are filled by their DEFAULT ON NULL values
INSERT INTO tram_stations (
  station_code,
  station_name,
  site_note,
  geom,
  geom_to_sopot,
  geom_to_crnomerec,
  osm_node_to_sopot,
  osm_node_to_crnomerec
)
VALUES
  ('A', 'Trg bana Josipa Jelačića', 'Paved square',
   SDO_GEOMETRY(15.976940, 45.812943), SDO_GEOMETRY(15.977282, 45.812866), SDO_GEOMETRY(15.976597, 45.813020),
   3857863481, 3857863482),
  ('B', 'Zrinjevac', 'Park with plane trees',
   SDO_GEOMETRY(15.977791, 45.809054), SDO_GEOMETRY(15.977767, 45.808981), SDO_GEOMETRY(15.977815, 45.809126),
   3845849157, 3845849158),
  ('C', 'Glavni kolodvor', 'Main railway station',
   SDO_GEOMETRY(15.978842, 45.805244), SDO_GEOMETRY(15.979252, 45.805253), SDO_GEOMETRY(15.978432, 45.805234),
   1718635554, 330184221),
  ('D', 'Autobusni kolodvor', 'Main bus terminal, large paved area',
   SDO_GEOMETRY(15.993778, 45.804000), SDO_GEOMETRY(15.993958, 45.803640), SDO_GEOMETRY(15.993597, 45.804360),
   2062222557, 330842509);

COMMIT;

-- Check SDO metadata - will be created upon spatial index creation
SELECT * FROM USER_SDO_GEOM_METADATA WHERE table_name = 'TRAM_STATIONS';

-- Create spatial index (optimized index for point geometries)
CREATE INDEX IF NOT EXISTS tram_stations_sidx
ON tram_stations (geom)
INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2 PARAMETERS ('layer_gtype=POINT cbtree_index=true');

-- If needed, drop the index
-- DROP INDEX tram_stations_sidx FORCE;

-- Re-check SDO metadata after spatial index creation
SELECT * FROM USER_SDO_GEOM_METADATA WHERE table_name = 'TRAM_STATIONS';

-- Show the data, filtered with the predefined SDO_GTYPE and SDO_SRID constants
SELECT
  s.station_code,
  s.station_name,
  s.tram_line,
  s.geom.sdo_point.x AS lon,
  s.geom.sdo_point.y AS lat,
  ROUND(SDO_GEOM.SDO_DISTANCE(s.geom_to_sopot, s.geom_to_crnomerec, 0.05, 'unit=M'), 1) AS stop_gap_m,
  s.data_source
FROM
  tram_stations s
WHERE
  s.geom.sdo_gtype = SDO_POINT2D
  AND s.geom.sdo_srid = SDO_LONLAT
ORDER BY
  s.station_code;

-- Use the spatial index: stations within 500 m of station A (Trg bana Josipa Jelačića)
SELECT
  s.station_code,
  s.station_name,
  ROUND(SDO_GEOM.SDO_DISTANCE(s.geom, a.geom, 0.05, 'unit=M')) AS distance_m
FROM
  tram_stations s,
  tram_stations a
WHERE
  a.station_code = 'A'
  AND SDO_WITHIN_DISTANCE(s.geom, a.geom, 'distance=500 unit=M') = 'TRUE'
ORDER BY
  distance_m;
