/*********************************************
 * Create Vector Tiles from a point data set
 *
 * Author: Karin Patenge
 * Date: May 2025
 *********************************************/

--
-- Documentation: https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/vector-tiles.html
-- Related blog posts:
-- 1. https://medium.com/@kpatenge/how-to-create-vector-tiles-from-spatial-data-managed-in-the-oracle-database-db662f2b5544
-- 2. https://blogs.oracle.com/database/post/make-better-maps-for-your-apps-with-spatial-vector-tiles-and-h3-in-oracle-database-23ai
--

-- Prerequisites:
-- 1. Load data provided as shape files into UNFALLORTE_2023_LR_BASISDLM using Spatial Studio
-- 2. Convert LRS to standard SDO_GEOMETRY data
-- 3. Validate the data set
-- 4. Fix errors if necessary
-- 5. Display data on a map


-- Convert LRS to standard SDO_GEOMETRY
BEGIN
  IF (
    SDO_LRS.CONVERT_TO_STD_LAYER('UNFALLORTE_2023_LR_BASISDLM', 'GEOM') = 'TRUE'
    )
  THEN
    DBMS_OUTPUT.PUT_LINE('Conversion from LRS_LAYER to STD_LAYER succeeded.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Conversion from LRS_LAYER to STD_LAYER failed.');
  END IF;
END;
/

-- Check loaded data
SELECT * FROM unfallorte_2023_lr_basisdlm FETCH FIRST 10 ROWS ONLY;

SELECT count(*) FROM unfallorte_2023_lr_basisdlm;
-- 269.048

-- Show accidents in Spatial Studio
-- Retrieve sample {z}/{x}/{y} using map settings

-- Fetch Vector Tile
SELECT SDO_UTIL.GET_VECTORTILE(
  TABLE_NAME => 'UNFALLORTE_2023_LR_BASISDLM',
  GEOM_COL_NAME => 'GEOM',
  ATT_COL_NAMES => SDO_STRING_ARRAY('UJAHR','UMONAT','USTUNDE','UWOCHENTAG','UART','UKATEGORIE','UTYP1'),
  TILE_X => 67,
  TILE_Y_PBF => 44,
  TILE_ZOOM => 7) AS vtile
FROM DUAL;

-- Create a REST module
BEGIN
  ORDS.DEFINE_MODULE(
    P_MODULE_NAME => 'accidents',
    P_BASE_PATH => '/ac2025/',
    P_ITEMS_PER_PAGE => 25,
    P_STATUS => 'PUBLISHED',
    P_COMMENTS => ''
  );
  COMMIT;
END;
/


-- Create a module template
BEGIN
  ORDS.DEFINE_TEMPLATE(
    P_MODULE_NAME => 'accidents',
    P_PATTERN => 'vt/:z/:x/:y',
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
    P_PATTERN => 'vt/:z/:x/:y',
    P_METHOD => 'GET',
    P_SOURCE_TYPE => ords.source_type_media,
    P_SOURCE =>
      'SELECT
        ''application/vnd.mapbox-vector-tile'' as mediatype,
        SDO_UTIL.GET_VECTORTILE(
          TABLE_NAME => ''UNFALLORTE_2023_LR_BASISDLM'',
          GEOM_COL_NAME => ''GEOM'',
          ATT_COL_NAMES => SDO_STRING_ARRAY(''UJAHR'',''UMONAT'',''USTUNDE'',''UWOCHENTAG'',''UART'',''UKATEGORIE'',''UTYP1''),
          TILE_X => :x,
          TILE_Y_PBF => :y,
          TILE_ZOOM => :z
        ) AS vtile
      FROM dual',
    P_ITEMS_PER_PAGE => 25,
    P_COMMENTS => ''
  );
  COMMIT;
END;
/

-- Fetch the URL of the REST endpoint using Database Actions

-- Show data using a single-page web app ./scripts/22_vector_tiles_single_page_app.html