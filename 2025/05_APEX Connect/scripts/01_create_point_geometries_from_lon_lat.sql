/*********************************************
 * Create point geometries from lon/lat values
 *
 * Author: Karin Patenge
 * Date: May 2025
 *********************************************/

--
-- Documentation: https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/spatial-developers-guide.pdf
--

-- Import the csv data set using APEX, SQL Developer, SQLcl, or another tool of your choice
-- Table name: govdata_street_lamps_nue

-- Add a column to convert lon/lat into SDO_GEOMETRY
ALTER TABLE govdata_street_lamps_nue
ADD (geometry SDO_GEOMETRY);

-- Fill the SDO_GEOMETRY column
UPDATE govdata_street_lamps_nue
SET geometry = SDO_GEOMETRY(longitude, latitude);

COMMIT;

-- Show the data
SELECT
  longitude,
  latitude,
  crs,
  lit,
  name,
  osm,
  geometry,
  -- derived data: DOT notation for data type SDO_GEOMETRY
  t.geometry.sdo_srid AS geom_srid,
  t.geometry.sdo_gtype AS geom_gtype,
  t.geometry.sdo_point.x AS geom_lon,
  t.geometry.sdo_point.y AS geom_lat
FROM
  govdata_street_lamps_nue t;

-- Check SDO metadata - will be created upon spatial index creation
SELECT * FROM USER_SDO_GEOM_METADATA;

-- Create spatial index (optimized index for point geometries)
CREATE INDEX govdata_street_lamps_nue_sidx
ON govdata_street_lamps_nue (geometry)
INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2 PARAMETERS ('layer_gtype=POINT cbtree_index=true');

-- If needed, drop the index
DROP INDEX govdata_street_lamps_nue_sidx FORCE;

-- Re-check SDO metadata after spatial index creation
SELECT * FROM USER_SDO_GEOM_METADATA;


