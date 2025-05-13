/*********************************************
 * Load GeoJSON data and convert it
 * to SDO_GEOMETRY using SDO_UTIL.FROM_GEOJSON
 * and JSON_VALUE
 *
 * Author: Karin Patenge
 * Date: May 2025
 *********************************************/

DROP TABLE geojson_tab PURGE;

CREATE TABLE geojson_tab (
  id number,
  geojson_col VARCHAR2(4000),
  geometry SDO_GEOMETRY,
  CONSTRAINT ensure_json_chk CHECK (geojson_col IS JSON)
);

-- Insert some data (2 points).
INSERT INTO geojson_tab(id, geojson_col)
VALUES (1, '{"type":"Point","coordinates":[+123.4,+10.1]}');

INSERT INTO geojson_tab(id, geojson_col)
VALUES (2, '{"type":"Point","coordinates":[+123.5,-10.1]}');

COMMIT;

SELECT * FROM geojson_tab;

-- For each geojson_col value, return the SDO_GEOMETRY equivalent
-- a) using JSON_VALUE
SELECT JSON_VALUE(geojson_col, '$.*' RETURNING SDO_GEOMETRY)
FROM geojson_tab;
-- b) using SDO_UTIL.FROM_GEOJSON
SELECT SDO_UTIL.FROM_GEOJSON(geojson_col)
FROM geojson_tab;

-- Write SDO_GEOMETRY
UPDATE geojson_tab
SET geometry = SDO_UTIL.FROM_GEOJSON(geojson_col);

COMMIT;

--
-- Use Spatial Studio to load the GeoJSON data set ./data/world_cities.geojson
-- Note: GeoJSON is automatically converted to SDO_GEOMETRY
--

--
-- Next steps:
-- 1. Display admin boundaries on a map in APEX
-- 2. Use Spatial Studio to load and visualize the data set
--




