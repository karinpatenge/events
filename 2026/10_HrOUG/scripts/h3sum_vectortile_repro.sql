--
-- Minimal reproduction: SDO_UTIL.H3SUM_VECTORTILE raises
--   ORA-06553: PLS-306: wrong number or types of arguments in call to 'SPLIT_180_MERIDIAN'
--   ORA-06512: at "MDSYS.SDO_UTIL", line 6428
--   ORA-06512: at "MDSYS.SDO_UTIL", line 16619
--
-- Seen on 2026-10-09 on Autonomous AI Database 26ai (Data Lakehouse workload) with the H3 summary table
-- ZG_LST_H3SUM, both without levelnum and with levelnum => 9 (notebook demo2_prep_zg_h3_cells.sqlnb, section 12).
-- This script uses three points and the call form of the SDO_UTIL.H3SUM_VECTORTILE reference example.
--

-- Database version for the report
SELECT version_full FROM product_component_version;

-- Three points: tram stops A, B, C in Zagreb (longitude, latitude)
DROP TABLE IF EXISTS h3sum_repro_h3 PURGE;
DROP TABLE IF EXISTS h3sum_repro_pts PURGE;

CREATE TABLE h3sum_repro_pts (id NUMBER, x NUMBER, y NUMBER);
INSERT INTO h3sum_repro_pts VALUES (1, 15.97694, 45.812943), (2, 15.977791, 45.809054), (3, 15.978842, 45.805244);
COMMIT;

-- H3 summary table, levels 0 to 10
BEGIN
  SDO_UTIL.H3SUM_CREATE_TABLE('H3SUM_REPRO_H3', 'H3SUM_REPRO_PTS', 'X, Y', 'ID,CNT', 10);
END;
/

-- Check: the summary table exists and holds the 3 points on every level
SELECT * FROM SDO_UTIL.H3SUM_LIST_TABLES();

SELECT levelnum, COUNT(*) AS hexagons, SUM(id_cnt) AS points
FROM h3sum_repro_h3
GROUP BY levelnum
ORDER BY levelnum;

-- Reproduction: call form of the reference example (explicit level, zoom 2; tile 2/2/1 contains Zagreb)
SELECT DBMS_LOB.GETLENGTH(
         SDO_UTIL.H3SUM_VECTORTILE(H3_TABLE => 'H3SUM_REPRO_H3', LEVELNUM => 1,
                                   TILE_X => 2, TILE_Y => 1, TILE_ZOOM => 2)) AS blobsize
FROM dual;

-- Clean up
DROP TABLE IF EXISTS h3sum_repro_h3 PURGE;
DROP TABLE IF EXISTS h3sum_repro_pts PURGE;
