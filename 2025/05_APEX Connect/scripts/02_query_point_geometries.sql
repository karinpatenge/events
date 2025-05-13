/*********************************************
 * Typical queries for point geometries
 *
 * Author: Karin Patenge
 * Date: May 2025
 *********************************************/

--
-- Documentation: https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/spatial-developers-guide.pdf
--

--
-- Spatial functions and operators used in this script:
--  * SDO_GEOM.SDO_CENTROID
--  * SDO_AGGR_UNION
--  * SDO_NN_DISTANCE
--  * SDO_AGGR_MBR
--  * SDO_POINTINPOLYGON (table function)
--

-- What is the center point of all street lamp locations?
WITH all_points_center AS (
  -- Aggregate first all points into one geometry. Then determine the center of gravity for that aggregated geometry
  SELECT
    SDO_GEOM.SDO_CENTROID(
      SDO_AGGR_UNION(
        SDOAGGRTYPE(
          geometry,
          0.05
        )
      ),
      0.05
    ) AS center_point
  FROM
    govdata_street_lamps_nue)
SELECT
  c.center_point.sdo_point.x AS lon,
  c.center_point.sdo_point.y AS lat
FROM
  all_points_center c;

-- How far away are the 5 nearest street lamps from a given point?
SELECT
  *
FROM (
  SELECT /*+ FIRST ROWS */
    SDO_NN_DISTANCE(1) AS dist_in_km,
    l.name,
    l.lit,
    l.osm,
    l.longitude,
    l.latitude
  FROM
    govdata_street_lamps_nue l
  WHERE
    SDO_NN(
      l.geometry,
      SDO_GEOMETRY(11.08, 49.44),
      'SDO_BATCH_SIZE=10 unit=km',
      1
    ) = 'TRUE'
  ORDER BY
    SDO_NN_DISTANCE(1)
)
WHERE
  ROWNUM <=5;

-- Which street lamps are inside a given query window?
SELECT /*+ PARALLEL(a, 4) */
  *
FROM
  TABLE(
    SDO_POINTINPOLYGON(
      CURSOR(
        SELECT
          *
        FROM
          govdata_street_lamps_nue
      ),                              -- cursor over the street lamps table
    (
      SELECT
        SDO_AGGR_MBR(l.geometry) AS geom
      FROM
        govdata_street_lamps_nue l
    ),                                -- query window as minimum bounding rectangle around all street lamps
    0.05
  )
) a;
