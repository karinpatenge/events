/*********************************************
 * Typical queries for point geometries
 *
 * Author: Karin Patenge
 * Date: May 2025
 *********************************************/

-- What is the center point of all street lamp locations?
WITH all_points_center AS (
  -- Aggregate first all points into one geometry. Then determine the center of gravity for that aggregated geometry
  SELECT
    SDO_GEOM.SDO_CENTROID(SDO_AGGR_UNION(SDOAGGRTYPE(geometry, 0.05)), 0.05) AS center_point
  FROM
    govdata_street_lamps_nue)
SELECT
  c.center_point.sdo_point.x AS lon,
  c.center_point.sdo_point.y AS lat
FROM
  all_points_center c;

