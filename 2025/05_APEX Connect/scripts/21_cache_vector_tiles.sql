/*********************************************
 * Create point geometries from lon/lat values
 *
 * Author: Karin Patenge
 * Date: May 2025
 *********************************************/

--
-- Documentation: https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/vector-tiles.html#GUID-CD83B85A-621D-44D7-9633-C4C1037FBED2
--

-- Enable cache for vector tiles
EXEC SDO_UTIL.ENABLE_VECTORTILE_CACHE('unfallorte_2023_lr_basisdlm', 'geom');

SELECT * FROM SDO_VECTOR_TILE_CACHE$INFO;

SELECT * FROM SDO_VECTOR_TILE_CACHE$TABLE;

-- Show data in single-page web app

SELECT COUNT(*) FROM SDO_VECTOR_TILE_CACHE$TABLE;

