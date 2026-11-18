--------------------------------------------------------------------------------
-- File       : 07_create_spatial_indexes.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Registers the spatial metadata, validates the geometries and
--              creates the spatial indexes, logs invalid geometries in
--              GEOMETRY_ERRORS and fixes them, then gathers statistics.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as the demo user, after 03_load_data.sql
--                sql doag2026@<tns_alias> @07_create_spatial_indexes.sql
-- Re-runnable: yes. Metadata is deleted and inserted again, existing
--              indexes are kept. With DEFINE rebuild = Y all spatial
--              indexes are created again.
-- Log        : logs/sql/07_create_spatial_indexes.log in the project folder,
--              overwritten on every run
--
-- Why this order (best practice for spatial indexes)
--   1. Load first, then index. 03_load_data.sql drops existing spatial
--      indexes before loading, so that no index has to be maintained
--      during the load.
--   2. Metadata before the index: dimensions, tolerance and SRID are kept
--      in USER_SDO_GEOM_METADATA. For SRID 4326 (geodetic) the tolerance
--      is given in metres: 0.05 m.
--   3. Validate geometries before indexing: invalid geometries return
--      wrong results, a non-point geometry in a point table makes
--      CREATE INDEX with layer_gtype=POINT fail.
--   4. SPATIAL_INDEX_V2 (recommended index type since 12.2) for all
--      geometry columns. Lines, polygons and mixed tables get an index
--      without parameters.
--   5. Index parameters only for pure point tables: layer_gtype=POINT and
--      cbtree_index=true, a composite B-tree instead of an R-tree, smaller
--      and faster for points. This also applies to the streams the demo
--      keeps writing into.
--   6. PARALLEL only for large tables (from parallel_min_rows rows on).
--      No table in the dataset is that large; the switch is meant for
--      larger OSM extracts.
--   7. Gather statistics afterwards, so that the optimizer knows the index.
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/07_create_spatial_indexes.log

-- Y = drop all spatial indexes and create them again
DEFINE rebuild           = Y

-- Tolerance in metres (geodetic data, SRID 4326)
DEFINE tolerance         = 0.05

-- From this number of rows on, the index is built in parallel
DEFINE parallel_min_rows = 100000
DEFINE parallel_degree   = 4

PROMPT
PROMPT === 07 Spatial metadata and spatial indexes ===

BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the demo user, not as ADMIN.');
  END IF;
END;
/

--==============================================================================
-- 1. Spatial metadata (before the index)
--    One row per geometry column. Longitude (X) before latitude (Y), SRID 4326.
--==============================================================================

PROMPT
PROMPT --- 1. USER_SDO_GEOM_METADATA
-- USER_SDO_GEOM_METADATA does not support MERGE (view with INSTEAD OF
-- triggers): delete the existing entries of these columns, then insert them.
DECLARE
  l_tables SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
             'ROAD_NODES', 'PROVIDERS', 'WATCH_STREAM', 'CAR_STREAM',
             'TRAIL_SEGMENTS', 'PARKING_LOTS', 'POIS', 'ZONES',
             'OSM_TRAILS', 'OSM_PARKING', 'OSM_POIS', 'OSM_ROADS',
             'OSM_HOSPITALS', 'OSM_BOUNDARIES', 'SYMPTOM_REPORTS');
  l_deleted PLS_INTEGER;
BEGIN
  DELETE FROM user_sdo_geom_metadata
  WHERE  column_name = 'GEOM'
  AND    table_name IN (SELECT t.COLUMN_VALUE FROM TABLE(l_tables) t);
  l_deleted := SQL%ROWCOUNT;
  COMMIT;

  FOR i IN 1 .. l_tables.COUNT LOOP
    INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
    VALUES (l_tables(i), 'GEOM',
            SDO_DIM_ARRAY(SDO_DIM_ELEMENT('Longitude', -180, 180, &tolerance),
                          SDO_DIM_ELEMENT('Latitude',   -90,  90, &tolerance)),
            4326);
  END LOOP;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('OK      USER_SDO_GEOM_METADATA: ' || l_deleted || ' entries deleted, '
                       || l_tables.COUNT || ' inserted');
END;
/

--==============================================================================
-- 2. and 3. Validate geometries, create indexes
--    One list for both steps: table and expected geometry type.
--    The expected type is checked for all tables (the MULTI types include
--    the simple type, MULTILINE also allows lines; mixed tables such as
--    OSM parking and POIs have no expected type). Index parameters are set
--    only for point tables: layer_gtype=POINT cbtree_index=true.
--==============================================================================

PROMPT
PROMPT --- 2. Validate geometries, 3. Create spatial indexes
DECLARE
  TYPE t_layer IS RECORD (table_name VARCHAR2(128), layer_gtype VARCHAR2(20));
  TYPE t_layers IS TABLE OF t_layer;
  l_layers t_layers := t_layers(
    t_layer('ROAD_NODES',      'POINT'),
    t_layer('PROVIDERS',       'POINT'),
    t_layer('WATCH_STREAM',    'POINT'),
    t_layer('CAR_STREAM',      'POINT'),
    t_layer('PARKING_LOTS',    'POINT'),
    t_layer('POIS',            'POINT'),
    t_layer('OSM_HOSPITALS',   'POINT'),
    t_layer('SYMPTOM_REPORTS', 'POINT'),         -- only the app report has a location
    t_layer('TRAIL_SEGMENTS',  'LINE'),
    t_layer('OSM_ROADS',       'MULTILINE'),
    t_layer('OSM_TRAILS',      'MULTILINE'),     -- paths and route relations
    t_layer('ZONES',           'POLYGON'),
    t_layer('OSM_BOUNDARIES',  'MULTIPOLYGON'),  -- city boundaries are multipolygons
    t_layer('OSM_PARKING',     NULL),            -- mixed: points and polygons
    t_layer('OSM_POIS',        NULL));           -- mixed: points and polygons

  l_index    VARCHAR2(128);
  l_params   VARCHAR2(200);
  l_blocked  BOOLEAN;
  l_allowed  VARCHAR2(20);
  l_rows     PLS_INTEGER;
  l_nulls    PLS_INTEGER;
  l_invalid  PLS_INTEGER;
  l_wrong    PLS_INTEGER;
  l_srid     PLS_INTEGER;
  l_exists   PLS_INTEGER;
  l_errors   PLS_INTEGER := 0;

  -- Allowed values of SDO_GTYPE MOD 100 per layer_gtype
  FUNCTION allowed_types(p_layer IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE p_layer
             WHEN 'POINT'        THEN '1'
             WHEN 'LINE'         THEN '2'
             WHEN 'POLYGON'      THEN '3'
             WHEN 'MULTIPOINT'   THEN '1,5'
             WHEN 'MULTILINE'    THEN '2,6'
             WHEN 'MULTIPOLYGON' THEN '3,7'
           END;
  END allowed_types;
BEGIN
  -- Rebuild? Then drop all spatial indexes first.
  IF UPPER('&rebuild') = 'Y' THEN
    FOR i IN (SELECT index_name FROM user_indexes
              WHERE  ityp_name IN ('SPATIAL_INDEX', 'SPATIAL_INDEX_V2')) LOOP
      EXECUTE IMMEDIATE 'DROP INDEX ' || DBMS_ASSERT.SIMPLE_SQL_NAME(i.index_name);
      DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD(i.index_name, 28) || ' dropped (rebuild = Y)');
    END LOOP;
  END IF;

  DBMS_OUTPUT.PUT_LINE(RPAD('Table', 24) || LPAD('Rows', 8) || LPAD('NULL', 7)
                       || LPAD('invalid', 11) || LPAD('wrong type', 12) || '  Index');
  FOR i IN 1 .. l_layers.COUNT LOOP
    l_allowed := allowed_types(l_layers(i).layer_gtype);

    -- 2. Check: rows, empty geometries, invalid ones, wrong type, SRID
    EXECUTE IMMEDIATE
      'SELECT COUNT(*),
              COUNT(CASE WHEN x.geom IS NULL THEN 1 END),
              COUNT(CASE WHEN x.geom IS NOT NULL
                          AND SDO_GEOM.VALIDATE_GEOMETRY_WITH_CONTEXT(x.geom, :tol) <> ''TRUE''
                         THEN 1 END),
              COUNT(CASE WHEN x.geom IS NOT NULL AND :allowed IS NOT NULL
                          AND INSTR('','' || :allowed || '','',
                                    '','' || MOD(x.geom.sdo_gtype, 100) || '','') = 0
                         THEN 1 END),
              COUNT(CASE WHEN x.geom IS NOT NULL AND NVL(x.geom.sdo_srid, -1) <> 4326 THEN 1 END)
       FROM   ' || DBMS_ASSERT.SIMPLE_SQL_NAME(l_layers(i).table_name) || ' x'
      INTO l_rows, l_nulls, l_invalid, l_wrong, l_srid
      -- one value per placeholder, in order: :tol, :allowed, :allowed
      USING &tolerance, l_allowed, l_allowed;

    -- A wrong SRID always stops the index. A wrong geometry type only stops
    -- the index of a point table, because only its index checks the type
    -- (layer_gtype=POINT).
    l_blocked := l_srid > 0 OR (l_wrong > 0 AND l_layers(i).layer_gtype = 'POINT');
    IF l_blocked THEN
      l_errors := l_errors + 1;
    END IF;

    -- 3. Create the index if it is missing and the data fits.
    --    Index parameters only for point tables: layer_gtype=POINT and
    --    cbtree_index=true. All other tables get a spatial index without
    --    parameters.
    l_index := l_layers(i).table_name || '_SIDX';
    SELECT COUNT(*) INTO l_exists FROM user_indexes WHERE index_name = l_index;

    l_params := CASE WHEN l_layers(i).layer_gtype = 'POINT'
                     THEN 'layer_gtype=POINT cbtree_index=true' END;

    IF l_exists > 0 THEN
      l_index := l_index || ' exists';
    ELSIF l_blocked THEN
      l_index := l_index || ' NOT created';
    ELSE
      EXECUTE IMMEDIATE
        'CREATE INDEX ' || l_index || ' ON ' || l_layers(i).table_name || ' (geom)'
        || ' INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2'
        || CASE WHEN l_params IS NOT NULL THEN ' PARAMETERS (''' || l_params || ''')' END
        || CASE WHEN l_rows >= &parallel_min_rows THEN ' PARALLEL &parallel_degree' END;
      l_index := l_index || ' created' || CASE WHEN l_params IS NOT NULL THEN ' (' || l_params || ')' END;
    END IF;

    DBMS_OUTPUT.PUT_LINE(CASE WHEN l_invalid + l_wrong + l_srid = 0 THEN 'OK      ' ELSE 'WARNING ' END
                         || RPAD(l_layers(i).table_name, 16) || LPAD(l_rows, 8) || LPAD(l_nulls, 7)
                         || LPAD(l_invalid, 11) || LPAD(l_wrong + l_srid, 12) || '  ' || l_index);
  END LOOP;

  IF l_errors > 0 THEN
    RAISE_APPLICATION_ERROR(-20021, l_errors || ' table(s) with wrong SRID or non-point geometries in a point table. '
                                    || 'Correct the data or the list in this script.');
  END IF;
END;
/

--==============================================================================
-- 4. Check the status of the indexes
--==============================================================================

PROMPT
PROMPT --- 4. Status of the spatial indexes
DECLARE
  l_bad PLS_INTEGER := 0;
BEGIN
  FOR i IN (SELECT index_name, status, domidx_status, domidx_opstatus
            FROM   user_indexes
            WHERE  ityp_name = 'SPATIAL_INDEX_V2'
            ORDER  BY index_name) LOOP
    IF i.status <> 'VALID' OR i.domidx_status <> 'VALID' OR i.domidx_opstatus <> 'VALID' THEN
      l_bad := l_bad + 1;
      DBMS_OUTPUT.PUT_LINE('WARNING ' || RPAD(i.index_name, 28) || i.status || ' / '
                           || i.domidx_status || ' / ' || i.domidx_opstatus);
    END IF;
  END LOOP;
  IF l_bad = 0 THEN
    DBMS_OUTPUT.PUT_LINE('OK      all spatial indexes VALID');
  ELSE
    RAISE_APPLICATION_ERROR(-20022, l_bad || ' spatial index(es) not VALID.');
  END IF;
END;
/

--==============================================================================
-- 5. Validate all geometries and log the errors in GEOMETRY_ERRORS
--    Step 2 only counts invalid geometries per table. This step stores each
--    invalid geometry with error code, message and context (from
--    SDO_GEOM.VALIDATE_GEOMETRY_WITH_CONTEXT), so that it can be inspected
--    and corrected. Covered are all SDO_GEOMETRY columns of all tables of the
--    current user. The tolerance comes from USER_SDO_GEOM_METADATA; without
--    metadata the default tolerance of this script applies.
--    GEOMETRY_ERRORS is recreated on every run and holds the latest result.
--    Errors are reported as WARNING and do not stop the script.
--    Note: depending on the number of spatial tables and the number and size
--    of their geometries, this step can take a while.
--==============================================================================

PROMPT
PROMPT --- 5. Validate geometries (errors in GEOMETRY_ERRORS)
DROP TABLE IF EXISTS geometry_errors PURGE;

CREATE TABLE IF NOT EXISTS geometry_errors (
  table_name    VARCHAR2(128)
                ANNOTATIONS (Display 'Table', Description 'Table with the invalid geometry'),
  column_name   VARCHAR2(128)
                ANNOTATIONS (Display 'Column', Description 'SDO_GEOMETRY column'),
  obj_rowid     ROWID
                ANNOTATIONS (Display 'Row ID', Description 'ROWID of the row in TABLE_NAME'),
  geometry      SDO_GEOMETRY
                ANNOTATIONS (Display 'Geometry', Description 'Copy of the invalid geometry'),
  tolerance     NUMBER
                ANNOTATIONS (Display 'Tolerance', Description 'Tolerance used for the validation', Unit 'm'),
  error_code    CHAR(5)
                ANNOTATIONS (Display 'Error code', Description 'ORA error number, e.g. 13349'),
  error_message VARCHAR2(256)
                ANNOTATIONS (Display 'Error message', Description 'Text of the ORA error'),
  error_context VARCHAR2(256)
                ANNOTATIONS (Display 'Error context', Description 'Position of the error, e.g. [Element <1>] [Ring <1>]'))
ANNOTATIONS (
  Display     'Geometry errors',
  Description 'Invalid geometries found by 07_create_spatial_indexes.sql, step 5; recreated on every run',
  Feature     'Spatial');

DECLARE
  default_tolerance NUMBER := &tolerance;
  commit_frequency  NUMBER := 100;
  geom_cursor       SYS_REFCURSOR;
  v_diminfo         SDO_DIM_ARRAY;
  v_srid            NUMBER;
  v_tolerance       NUMBER;
  v_rowid           ROWID;
  v_geometry        SDO_GEOMETRY;
  v_num_rows        NUMBER;
  v_num_errors      NUMBER;
  v_total_errors    NUMBER := 0;
  v_error_code      CHAR(5);
  v_error_message   VARCHAR2(256);
  v_error_context   VARCHAR2(256);
  v_status          VARCHAR2(256);
BEGIN
  -- Process all spatial tables owned by the current user (tables only, no views)
  FOR t IN (SELECT c.table_name, c.column_name
            FROM   user_tab_columns c
            WHERE  c.data_type = 'SDO_GEOMETRY'
            AND    c.table_name <> 'GEOMETRY_ERRORS'
            AND    c.table_name IN (SELECT u.table_name FROM user_tables u)
            ORDER  BY c.table_name, c.column_name) LOOP

    -- Get the tolerance from the metadata
    BEGIN
      SELECT diminfo, srid
      INTO   v_diminfo, v_srid
      FROM   user_sdo_geom_metadata
      WHERE  table_name  = t.table_name
      AND    column_name = t.column_name;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        v_diminfo := NULL;
        v_srid    := NULL;
    END;

    -- Without metadata use the default tolerance
    IF v_diminfo IS NULL THEN
      v_tolerance := default_tolerance;
    ELSE
      v_tolerance := v_diminfo(1).sdo_tolerance;
    END IF;

    -- Process the geometries
    v_num_rows   := 0;
    v_num_errors := 0;
    OPEN geom_cursor FOR 'SELECT rowid, ' || DBMS_ASSERT.ENQUOTE_NAME(t.column_name, FALSE)
                         || ' FROM ' || DBMS_ASSERT.ENQUOTE_NAME(t.table_name, FALSE);
    LOOP
      v_status := NULL;

      -- Fetch the geometry
      FETCH geom_cursor INTO v_rowid, v_geometry;
      EXIT WHEN geom_cursor%NOTFOUND;

      v_num_rows := v_num_rows + 1;
      IF v_geometry IS NOT NULL THEN
        -- Validate the geometry
        v_status := SDO_GEOM.VALIDATE_GEOMETRY_WITH_CONTEXT(v_geometry, v_tolerance);

        -- Log the error (if any)
        IF v_status <> 'TRUE' THEN
          v_num_errors := v_num_errors + 1;
          -- Format the error message
          IF LENGTH(v_status) >= 5 THEN
            v_error_code    := SUBSTR(v_status, 1, 5);
            v_error_message := SQLERRM(-v_error_code);
            v_error_context := SUBSTR(v_status, 7);
          ELSE
            v_error_code    := v_status;
            v_error_message := NULL;
            v_error_context := NULL;
          END IF;
          -- Write the error
          INSERT INTO geometry_errors (table_name, column_name, obj_rowid, geometry, tolerance,
                                       error_code, error_message, error_context)
          VALUES (t.table_name, t.column_name, v_rowid, v_geometry, v_tolerance,
                  v_error_code, v_error_message, v_error_context);
        END IF;

        -- Commit as necessary
        IF MOD(v_num_rows, commit_frequency) = 0 THEN
          COMMIT;
        END IF;
      END IF;
    END LOOP;
    CLOSE geom_cursor;
    COMMIT;

    v_total_errors := v_total_errors + v_num_errors;
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_num_errors = 0 THEN 'OK      ' ELSE 'WARNING ' END
                         || RPAD(t.table_name || '.' || t.column_name, 32) || LPAD(v_num_rows, 8)
                         || ' rows, ' || v_num_errors || ' invalid (tolerance ' || v_tolerance || ')');
  END LOOP;

  -- Final commit
  COMMIT;
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_total_errors = 0 THEN 'OK      ' ELSE 'WARNING ' END
                       || v_total_errors || ' invalid geometries in total, details in GEOMETRY_ERRORS');
END;
/

-- Check results
COLUMN table_name    FORMAT A28
COLUMN error_code    FORMAT A10
COLUMN error_message FORMAT A60 TRUNCATED
COLUMN error_context FORMAT A40 TRUNCATED

PROMPT --- Errors by table and error code
SELECT table_name, error_code, COUNT(*) AS errors
FROM   geometry_errors
GROUP  BY table_name, error_code
ORDER  BY table_name, error_code;

PROMPT --- Errors by error code and table
SELECT error_code, table_name, COUNT(*) AS errors
FROM   geometry_errors
GROUP  BY error_code, table_name
ORDER  BY error_code, table_name;

PROMPT --- Error details
SELECT table_name, obj_rowid, error_message, error_context
FROM   geometry_errors
ORDER  BY table_name, obj_rowid;

--==============================================================================
-- 5a. Fix invalid geometries from GEOMETRY_ERRORS
--    SDO_UTIL.RECTIFY_GEOMETRY repairs typical errors such as the wrong
--    ring orientation (ORA-13367), duplicate vertices (ORA-13356) or
--    self-intersecting polygons (ORA-13349). A repaired geometry is written
--    back to its table only if it is valid afterwards; its row is then
--    removed from GEOMETRY_ERRORS. Geometries that cannot be repaired
--    (ORA-13199) stay in GEOMETRY_ERRORS and are reported as WARNING.
--    The spatial index is maintained by the UPDATE.
--==============================================================================

PROMPT
PROMPT --- 5a. Fix invalid geometries
DECLARE
  -- "ORA-13199: the given geometry cannot be rectified"
  cannot_rectify EXCEPTION;
  PRAGMA EXCEPTION_INIT(cannot_rectify, -13199);
  v_geometry_fixed SDO_GEOMETRY;
  v_fixed          PLS_INTEGER := 0;
  v_failed         PLS_INTEGER := 0;
BEGIN
  -- Process the invalid geometries
  FOR e IN (SELECT ROWID AS err_rowid, table_name, column_name, obj_rowid, tolerance, geometry, error_code
            FROM   geometry_errors
            ORDER  BY table_name, column_name) LOOP
    -- Try to rectify the geometry; NULL if it cannot be repaired
    BEGIN
      v_geometry_fixed := SDO_UTIL.RECTIFY_GEOMETRY(e.geometry, e.tolerance);
    EXCEPTION
      WHEN cannot_rectify THEN
        v_geometry_fixed := NULL;
    END;

    IF v_geometry_fixed IS NOT NULL
       AND SDO_GEOM.VALIDATE_GEOMETRY_WITH_CONTEXT(v_geometry_fixed, e.tolerance) = 'TRUE' THEN
      -- Update the base table with the rectified geometry
      EXECUTE IMMEDIATE 'UPDATE ' || DBMS_ASSERT.ENQUOTE_NAME(e.table_name, FALSE)
                        || ' SET ' || DBMS_ASSERT.ENQUOTE_NAME(e.column_name, FALSE)
                        || ' = :g WHERE ROWID = :r'
        USING v_geometry_fixed, e.obj_rowid;

      -- Remove the fixed and validated geometry from the error log
      DELETE FROM geometry_errors WHERE ROWID = e.err_rowid;
      v_fixed := v_fixed + 1;
      DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD(e.table_name || '.' || e.column_name, 32)
                           || ' ' || e.obj_rowid || ' fixed (error ' || e.error_code || ')');
    ELSE
      v_failed := v_failed + 1;
      DBMS_OUTPUT.PUT_LINE('WARNING ' || RPAD(e.table_name || '.' || e.column_name, 32)
                           || ' ' || e.obj_rowid || ' cannot be fixed (error ' || e.error_code || ')');
    END IF;

    COMMIT;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_failed = 0 THEN 'OK      ' ELSE 'WARNING ' END
                       || v_fixed || ' geometries fixed, ' || v_failed || ' remaining in GEOMETRY_ERRORS');
END;
/

-- Check remaining errors
PROMPT --- Remaining errors by table and error code
SELECT table_name, error_code, COUNT(*) AS errors
FROM   geometry_errors
GROUP  BY table_name, error_code
ORDER  BY table_name, error_code;

PROMPT --- Remaining errors by error code and table
SELECT error_code, table_name, COUNT(*) AS errors
FROM   geometry_errors
GROUP  BY error_code, table_name
ORDER  BY error_code, table_name;

PROMPT --- Remaining error details
SELECT table_name, obj_rowid, error_message, error_context
FROM   geometry_errors
ORDER  BY table_name, obj_rowid;

--==============================================================================
-- 6. Statistics for the tables with geometry (including indexes)
--==============================================================================

PROMPT
PROMPT --- 6. Statistics
BEGIN
  -- tables only
  FOR t IN (SELECT m.table_name
            FROM   user_sdo_geom_metadata m
            WHERE  m.table_name IN (SELECT u.table_name FROM user_tables u)
            ORDER  BY m.table_name) LOOP
    DBMS_STATS.GATHER_TABLE_STATS(ownname => USER, tabname => t.table_name, cascade => TRUE);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('OK      Statistics gathered');
END;
/

--==============================================================================
-- 7. Overview
--==============================================================================

PROMPT
PROMPT --- 7. Spatial indexes
SELECT i.table_name,
       i.index_name,
       i.parameters,
       (SELECT d.sdo_tolerance
        FROM   TABLE(m.diminfo) d
        WHERE  d.sdo_dimname = 'Longitude') AS tolerance_m,
       m.srid
FROM   user_indexes i
JOIN   user_sdo_geom_metadata m
  ON   m.table_name = i.table_name
WHERE  i.ityp_name = 'SPATIAL_INDEX_V2'
ORDER  BY i.table_name;

PROMPT
PROMPT Done. Continue with 08_create_rdf_network.sql.

SPOOL OFF
