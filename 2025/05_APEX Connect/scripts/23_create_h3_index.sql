/*********************************************
 * Create H3 Index from a point data set
 *
 * Author: Karin Patenge
 * Date: May 2025
 *********************************************/

--
-- Documentation: https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/h3-indexing.html
-- Related links:
-- 1. https://community.oracle.com/customerconnect/events/606221-oci-developer-coaching-add-fast-and-scalable-maps-to-your-apps-with-vector-tiles-and-h3-in-oracle-database-23ai
-- 2. https://elufasys.com/enhance-your-app-maps-using-spatial-vector-tiles-and-h3-in-oracle-database-23ai/
-- 3. https://lidagholizadeh.blogspot.com/2024/12/implementing-h3-index-for-spatial-data.html
--

-- Use the same data set as in ./scripts/20_create_vector_tiles.sql

-- Clean up
DROP TABLE unfallorte_2023_lr_basisdlm_h3 PURGE;
DELETE FROM USER_SDO_GEOM_METADATA WHERE TABLE_NAME = 'UNFALLORTE_2023_LR_BASISDLM_H3';
COMMIT;

-- Create H3 Index using SDO_UTIL.H3SUM_CREATE_TABLE procedure
-- to create an H3 summary table which simply counts the number of points that are combined into each hex
BEGIN
  SDO_UTIL.H3SUM_CREATE_TABLE(
    TABLE_OUT => 'unfallorte_2023_lr_basisdlm_h3',
    TABLE_IN => 'unfallorte_2023_lr_basisdlm',
    GEOMCOL_SPEC => 'geom',
    COL_SPEC => '1,CNT',
    MAX_H3_LEVEL => '6'
  );
END;
/

SELECT * FROM unfallorte_2023_lr_basisdlm_h3 ORDER BY levelnum ;

SELECT
  SDO_UTIL.H3SUM_VECTORTILE(
    H3_TABLE => 'unfallorte_2023_lr_basisdlm_h3',
    LEVELNUM => 6,
    TILE_X => 67,
    TILE_Y => 44,
    TILE_ZOOM => 7) AS h3sum_vtile
FROM
  DUAL;

SELECT
  DBMS_LOB.GETLENGTH(
    SDO_UTIL.H3SUM_VECTORTILE(
      H3_TABLE => 'unfallorte_2023_lr_basisdlm_h3',
      LEVELNUM => 6,
      TILE_X => 67,
      TILE_Y => 44,
      TILE_ZOOM => 7
    )
  ) AS blobsize
FROM DUAL;

-- Create a module template
BEGIN
  ORDS.DEFINE_TEMPLATE(
    P_MODULE_NAME => 'accidents',
    P_PATTERN => 'h3vt/:z/:x/:y',
    P_PRIORITY => 0,
    P_ETAG_TYPE => 'HASH',
    P_COMMENTS => ''
  );
  COMMIT;
END;
/

-- Create a GET handler
BEGIN
  ORDS.DEFINE_HANDLER(
    P_MODULE_NAME => 'accidents',
    P_PATTERN => 'h3vt/:z/:x/:y',
    P_METHOD => 'GET',
    P_SOURCE_TYPE => ords.source_type_media,
    P_SOURCE =>
      'SELECT
        ''application/vnd.mapbox-vector-tile'' as mediatype,
        SDO_UTIL.H3SUM_VECTORTILE(
          H3_TABLE => 'unfallorte_2023_lr_basisdlm_h3',
          LEVELNUM =>
            CASE
              WHEN z<=5 THEN z*1
              WHEN z BETWEEN 6 AND 9 THEN z-1
              WHEN z BETWEEN 10 AND 13 THEN z-2
              WHEN z BETWEEN 14 AND 16 THEN z-3
              WHEN z BETWEEN 17 AND 19 THEN z-4
              WHEN z>=20 THEN 15
            END,
          TILE_X => :x,
          TILE_Y_PBF => :y,
          TILE_ZOOM => a.z
        )
      FROM
        (SELECT :z AS z FROM DUAL) a',
    P_ITEMS_PER_PAGE => 25,
    P_COMMENTS => ''
  );
  COMMIT;
END;
/

https://wguwywegel1ojah-kpadw.adb.eu-frankfurt-1.oraclecloudapps.com/ords/spatialuser/ac2025/h3vt/{z}/{x}/{y}.pbf