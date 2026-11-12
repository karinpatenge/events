/*********************************************
 * A simple route request
 *
 * Author: Karin Patenge
 * Date: May 2025
 *********************************************/

-- Prerequisite
-- Execute as ADMIN
EXEC SDO_GCDR.ELOC_GRANT_ACCESS('SPATIALUSER');

-- Execute the rest as application user
SELECT
  SDO_GCDR.ELOC_ROUTE(
    'fastest',
    'km',
    'minute',
    7.722007596124917, 48.266219343979365,
    7.72778999617931, 48.26059642454351,
    'auto') AS t
FROM DUAL;


WITH x AS (
  SELECT SDO_GCDR.ELOC_ROUTE(
    'fastest',
    'km',
    'minute',
    7.722007596124917, 48.266219343979365,
    7.72778999617931, 48.26059642454351,
    'auto') AS t
  FROM DUAL
  )
  SELECT
    JSON_VALUE(t, '$.routeResponse.route.time') AS time,
    JSON_VALUE(t, '$.routeResponse.route.distance') AS dist,
    JSON_VALUE(t, '$.routeResponse.route.geometry' RETURNING CLOB
  ) AS GEOM
FROM x;

SELECT
  SDO_GCDR.ELOC_ROUTE_GEOM(
    'shortest',
    7.722007596124917, 48.266219343979365,
    7.72778999617931, 48.26059642454351,
    'truck'
  ) route_geom
FROM DUAL;

SELECT
  SDO_UTIL.TO_WKT(
    SDO_GCDR.ELOC_ROUTE_GEOM(
      'shortest',
      7.722007596124917, 48.266219343979365,
      7.72778999617931, 48.26059642454351,
      'truck'
    )
  ) route_wkt
FROM DUAL;

SELECT
  SDO_UTIL.TO_GEOJSON(
    SDO_GCDR.ELOC_ROUTE_GEOM(
      'shortest',
      7.722007596124917, 48.266219343979365,
      7.72778999617931, 48.26059642454351,
      'truck'
    )
  ) route_geojson
FROM DUAL;