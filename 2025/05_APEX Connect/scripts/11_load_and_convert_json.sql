/*********************************************
 * Load JSON data using APEX and convert it
 * to SDO_GEOMETRY using SDO_UTIL.FROM_JSON
 *
 * Author: Karin Patenge
 * Date: May 2025
 *********************************************/

--
-- Prerequisites:
-- 1. SDO_UTIL.FROM_JSON function is supported only if Oracle JVM is enabled on your ADB.ALTER
-- 2. Load data set ./data/world-administrative-boundaries.json using APEX
--


-- Enable Oracle JVM as user ADMIN
BEGIN
   DBMS_CLOUD_ADMIN.ENABLE_FEATURE(
       feature_name => 'JAVAVM' );
END;
/

-- Add column to store SDO_GEOMETRY object
ALTER TABLE world_admin_boundaries_json
ADD (boundary_geom SDO_GEOMETRY);

-- Convert JSON to SDO_GEOMETRY as application user
SELECT
  SDO_UTIL.FROM_JSON(geo_shape_geometry)
FROM
  world_admin_boundaries_json
FETCH FIRST 10 ROWS ONLY;

UPDATE
  world_admin_boundaries_json
SET
  boundary_geom = SDO_UTIL.FROM_JSON(geo_shape_geometry);

COMMIT;

CREATE INDEX world_admin_boundaries_boundary_sidx
ON world_admin_boundaries_json (boundary_geom)
INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2;

ALTER TABLE world_admin_boundaries_json
ADD (geo_point_2d_geom SDO_GEOMETRY);

UPDATE
  world_admin_boundaries_json
SET
  geo_point_2d_geom = SDO_GEOMETRY(geo_point_2d_lon, geo_point_2d_lat);

COMMIT;

CREATE INDEX world_admin_boundaries_geo_point_2d_sidx
ON world_admin_boundaries_json (geo_point_2d_geom)
INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2  PARAMETERS ('layer_gtype=POINT cbtree_index=true');

SELECT * FROM user_sdo_geom_metadata ORDER BY 1;

-- Validate geometries
DECLARE
  -- Declare a custom exception for uncorrectable geometries
  -- "ORA-13199: the given geometry cannot be rectified"
  cannot_rectify EXCEPTION;
  PRAGMA EXCEPTION_INIT(cannot_rectify, -13199);
  v_geometry_fixed SDO_GEOMETRY;
BEGIN
  -- Process the invalid geometries
  FOR cur IN (
    SELECT rowid, boundary_geom
    FROM world_admin_boundaries_json
    WHERE SDO_GEOM.VALIDATE_GEOMETRY_WITH_CONTEXT(boundary_geom, 0.005) != 'TRUE'
  )
  LOOP
    -- Try and rectify the geometry.
    -- Throws an exception if it cannot be corrected
    BEGIN
      v_geometry_fixed := SDO_UTIL.RECTIFY_GEOMETRY (cur.boundary_geom, 0.005);
    EXCEPTION
      WHEN cannot_rectify THEN
        v_geometry_fixed := null;
    END;
    IF v_geometry_fixed IS NOT NULL THEN
      -- Update the base table with the rectified geometry
      UPDATE world_admin_boundaries_json
      SET boundary_geom = v_geometry_fixed
      WHERE rowid = cur.rowid;
      DBMS_OUTPUT.PUT_LINE('Successfully corrected geometry rowid='||cur.rowid);
    ELSE
      DBMS_OUTPUT.PUT_LINE('*** Unable to correct geometry rowid='||cur.rowid);
    END IF;
    COMMIT;

  END LOOP;
END;
/

--
-- Next steps:
-- 1. Display admin boundaries on a map in APEX
--




