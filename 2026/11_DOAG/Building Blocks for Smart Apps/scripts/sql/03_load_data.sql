--------------------------------------------------------------------------------
-- File       : 03_load_data.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Loads the dataset from folder data into the tables from
--              02_create_tables.sql and gathers statistics.
--              Spatial indexes are created afterwards by
--              07_create_spatial_indexes.sql, the RDF data is loaded by
--              09a_load_knee_kg.sql and 09b_load_fma.sql.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Tool       : SQLcl (LOAD is a SQLcl command)
-- Run        : in folder scripts\sql, so that the relative paths are correct:
--                cd <project>\scripts\sql
--                sql doag2026@<tns_alias> @03_load_data.sql
-- Re-runnable: yes. Target and staging tables are emptied first.
--              Existing spatial indexes are dropped before loading
--              (loading without index maintenance is faster); run 07 afterwards.
-- Log        : logs/sql/03_load_data.log in the project folder,
--              overwritten on every run
--
-- How each file is loaded
--   CSV            SQLcl LOAD into a staging table (all columns text),
--                  then INSERT ... SELECT with explicit conversions
--   JSON, GeoJSON, NDJSON
--                  SQLcl LOAD does not read JSON. All JSON, GeoJSON and
--                  NDJSON files are therefore stored in chunks of at most
--                  1000 characters in data/_load/json_chunks.csv
--                  (delimiter `). SQLcl LOAD into STG_JSON_CHUNKS, PL/SQL
--                  reassembles the chunks into documents in STG_JSON_DOCS
--                  (one document per feature or per NDJSON line), then
--                  JSON_TABLE and SDO_UTIL.FROM_GEOJSON
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET TIMING OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/03_load_data.log

-- Path to the data folder, relative to the current directory (folder scripts/sql)
DEFINE data_dir = ../../data

-- Demo area: bounding box of the Overpass query in osm_trails.geojson
-- (south, west, north, east = 49.755, 11.370, 49.795, 11.460). The hiking
-- route relations in OSM_TRAILS are clipped to it in step 4d.
DEFINE area_min_lon = 11.370
DEFINE area_min_lat = 49.755
DEFINE area_max_lon = 11.460
DEFINE area_max_lat = 49.795

-- Expected row counts. Adjust here after changing the dataset.
DEFINE exp_road_nodes        = 22
DEFINE exp_road_links        = 28
DEFINE exp_providers         = 28
DEFINE exp_devices           = 10
DEFINE exp_patients          = 25
DEFINE exp_appointment_slots = 435
DEFINE exp_provider_rel      = 23
DEFINE exp_patient_rel       = 27
DEFINE exp_case_notes        = 290
DEFINE exp_watch_stream      = 2051
DEFINE exp_car_stream        = 267
DEFINE exp_fhir_bundles      = 1000
DEFINE exp_symptom_reports   = 1459
DEFINE exp_diagnoses         = 1326
DEFINE exp_medication_recs   = 1331
DEFINE exp_json_chunks       = 23685
DEFINE exp_json_docs         = 16550
DEFINE exp_json_layers       = 12

PROMPT
PROMPT === 03 Load dataset from &data_dir ===

BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the demo user, not as ADMIN.');
  END IF;
END;
/

-- Decimal point in the CSV files, independent of the client setting
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

-- No parallel DML. Autonomous AI Database enables parallel DML by default for
-- the HIGH and MEDIUM services. A parallel INSERT into a child table (e.g.
-- APPOINTMENT_SLOTS) after inserting into its parent tables (PROVIDERS,
-- DEVICES) in the same transaction fails with ORA-12839. The data volumes
-- here are small, so serial DML is fast enough.
ALTER SESSION DISABLE PARALLEL DML;

--==============================================================================
-- 0. Drop spatial indexes, empty target tables (children before parents)
--    Without a spatial index, DELETE and INSERT run without index maintenance.
--    07_create_spatial_indexes.sql recreates the indexes after loading.
--==============================================================================

PROMPT
PROMPT --- 0. Drop spatial indexes, empty target tables
BEGIN
  FOR i IN (SELECT index_name FROM user_indexes
            WHERE  ityp_name IN ('SPATIAL_INDEX', 'SPATIAL_INDEX_V2')) LOOP
    EXECUTE IMMEDIATE 'DROP INDEX ' || DBMS_ASSERT.SIMPLE_SQL_NAME(i.index_name);
    DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD(i.index_name, 28) || ' dropped');
  END LOOP;

  FOR t IN (SELECT COLUMN_VALUE AS table_name
            FROM   TABLE(SYS.ODCIVARCHAR2LIST(
                     'MEDICATION_RECOMMENDATIONS', 'DIAGNOSES', 'SYMPTOM_REPORTS',
                     'WATCH_STREAM', 'CAR_STREAM',
                     'PATIENT_PROVIDER_RELATIONS', 'PROVIDER_RELATIONS', 'APPOINTMENT_SLOTS',
                     'DEVICES', 'PATIENTS', 'PROVIDERS', 'ROAD_LINKS', 'ROAD_NODES',
                     'CASE_NOTES', 'TRAIL_SEGMENTS', 'PARKING_LOTS', 'POIS', 'ZONES',
                     'OSM_TRAILS', 'OSM_PARKING', 'OSM_POIS', 'OSM_ROADS', 'OSM_HOSPITALS',
                     'OSM_BOUNDARIES', 'OSM_LAYERS',
                     'STG_JSON_DOCS')))
  LOOP
    EXECUTE IMMEDIATE 'DELETE FROM ' || DBMS_ASSERT.SIMPLE_SQL_NAME(t.table_name);
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('OK      Target tables emptied');
END;
/

--==============================================================================
-- 1. CSV files into the staging tables
--==============================================================================

PROMPT
PROMPT --- 1. Load CSV files (SQLcl LOAD)
SET LOADFORMAT DEFAULT
SET LOADFORMAT CSV DELIMITER , ENCLOSURES "" COLUMN_NAMES ON ENCODING UTF8
SET LOAD DEFAULT
SET LOAD BATCH_ROWS 1000 BATCHES_PER_COMMIT 10 ERRORS 0 TRUNCATE ON UNKNOWN_COLUMNS_FAIL ON

LOAD stg_road_nodes                 &data_dir/spatial/road_nodes.csv
LOAD stg_road_links                 &data_dir/spatial/road_links.csv
LOAD stg_providers                  &data_dir/graph/providers.csv
LOAD stg_devices                    &data_dir/graph/devices.csv
LOAD stg_patients                   &data_dir/graph/patients.csv
LOAD stg_appointment_slots          &data_dir/graph/appointment_slots.csv
LOAD stg_provider_relations         &data_dir/graph/provider_relations.csv
LOAD stg_patient_provider_relations &data_dir/graph/patient_provider_relations.csv
LOAD stg_case_notes                 &data_dir/casebase/case_notes.csv
LOAD stg_watch_stream               &data_dir/stream/watch_stream_jonas.csv
LOAD stg_car_stream                 &data_dir/stream/car_stream_friend.csv

-- LOAD does not abort the script on errors. Therefore count the rows here.
DECLARE
  TYPE t_check IS RECORD (table_name VARCHAR2(128), expected PLS_INTEGER);
  TYPE t_checks IS TABLE OF t_check;
  l_checks t_checks := t_checks(
    t_check('STG_ROAD_NODES',                 &exp_road_nodes),
    t_check('STG_ROAD_LINKS',                 &exp_road_links),
    t_check('STG_PROVIDERS',                  &exp_providers),
    t_check('STG_DEVICES',                    &exp_devices),
    t_check('STG_PATIENTS',                   &exp_patients),
    t_check('STG_APPOINTMENT_SLOTS',          &exp_appointment_slots),
    t_check('STG_PROVIDER_RELATIONS',         &exp_provider_rel),
    t_check('STG_PATIENT_PROVIDER_RELATIONS', &exp_patient_rel),
    t_check('STG_CASE_NOTES',                 &exp_case_notes),
    t_check('STG_WATCH_STREAM',               &exp_watch_stream),
    t_check('STG_CAR_STREAM',                 &exp_car_stream));
  l_cnt PLS_INTEGER;
BEGIN
  FOR i IN 1 .. l_checks.COUNT LOOP
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || l_checks(i).table_name INTO l_cnt;
    IF l_cnt <> l_checks(i).expected THEN
      RAISE_APPLICATION_ERROR(-20010, l_checks(i).table_name || ': ' || l_cnt
                                      || ' rows, expected ' || l_checks(i).expected);
    END IF;
    DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD(l_checks(i).table_name, 32) || LPAD(l_cnt, 8));
  END LOOP;
END;
/

--==============================================================================
-- 2. Staging -> target tables (parents before children)
--    Numbers with decimal point, times local Europe/Berlin, true/false -> BOOLEAN
--==============================================================================

PROMPT
PROMPT --- 2. Convert CSV data
INSERT INTO road_nodes (node_id, name, lat, lon, geom)
SELECT node_id, name, TO_NUMBER(lat), TO_NUMBER(lon),
       SDO_GEOMETRY(2001, 4326, SDO_POINT_TYPE(TO_NUMBER(lon), TO_NUMBER(lat), NULL), NULL, NULL)
FROM   stg_road_nodes;
COMMIT;

INSERT INTO road_links (link_id, start_node_id, end_node_id, road_class,
                        speed_kmh, length_m, cost_s, direction)
SELECT link_id, start_node_id, end_node_id, road_class,
       TO_NUMBER(speed_kmh), TO_NUMBER(length_m), TO_NUMBER(cost_s), direction
FROM   stg_road_links;
COMMIT;

INSERT INTO providers (provider_id, name, provider_type, specialty, city, lat, lon,
                       nearest_road_node_id, accepts_acute, geom)
SELECT provider_id, name, provider_type, specialty, city, TO_NUMBER(lat), TO_NUMBER(lon),
       nearest_road_node_id,
       CASE accepts_acute WHEN 'J' THEN TRUE WHEN 'N' THEN FALSE END,
       SDO_GEOMETRY(2001, 4326, SDO_POINT_TYPE(TO_NUMBER(lon), TO_NUMBER(lat), NULL), NULL, NULL)
FROM   stg_providers;
COMMIT;

INSERT INTO devices (device_id, provider_id, modality, field_strength_t, design)
SELECT device_id, provider_id, modality, TO_NUMBER(field_strength_t), design
FROM   stg_devices;
COMMIT;

INSERT INTO patients (patient_id, first_name, last_initial, birth_year, sex,
                      home_city, insurance, gp_provider_id)
SELECT patient_id, first_name, last_initial, TO_NUMBER(birth_year), sex,
       home_city, insurance, gp_provider_id
FROM   stg_patients;
COMMIT;

INSERT INTO appointment_slots (slot_id, provider_id, device_id, slot_start,
                               duration_min, slot_type, status)
SELECT slot_id, provider_id, device_id,
       FROM_TZ(TO_TIMESTAMP(slot_start, 'YYYY-MM-DD HH24:MI:SS'), 'Europe/Berlin'),
       TO_NUMBER(duration_min), slot_type, status
FROM   stg_appointment_slots;
COMMIT;

INSERT INTO provider_relations (relation_id, src_provider_id, dst_provider_id, relation_type)
SELECT relation_id, src_provider_id, dst_provider_id, relation_type
FROM   stg_provider_relations;
COMMIT;

INSERT INTO patient_provider_relations (relation_id, patient_id, provider_id, relation_type, since)
SELECT relation_id, patient_id, provider_id, relation_type, TO_DATE(since, 'YYYY-MM-DD')
FROM   stg_patient_provider_relations;
COMMIT;

INSERT INTO case_notes (case_id, recorded_on, age, sex, body_region, side, note_text,
                        diagnosis_code, diagnosis_label, confirmed_by)
SELECT case_id, TO_DATE(recorded_on, 'YYYY-MM-DD'), TO_NUMBER(age), sex, body_region, side,
       note_text, diagnosis_code, diagnosis_label, confirmed_by
FROM   stg_case_notes;
COMMIT;

INSERT INTO watch_stream (device_id, seq_no, patient_id, event_ts, ingest_ts, buffered,
                          lat, lon, ele_m, hr_bpm, cadence_spm, acc_peak_g, battery_pct,
                          phase, geom)
SELECT device_id, TO_NUMBER(seq_no), patient_id,
       FROM_TZ(TO_TIMESTAMP(event_ts,  'YYYY-MM-DD HH24:MI:SS'), 'Europe/Berlin'),
       FROM_TZ(TO_TIMESTAMP(ingest_ts, 'YYYY-MM-DD HH24:MI:SS'), 'Europe/Berlin'),
       CASE LOWER(buffered) WHEN 'true' THEN TRUE WHEN 'false' THEN FALSE END,
       TO_NUMBER(lat), TO_NUMBER(lon), TO_NUMBER(ele_m), TO_NUMBER(hr_bpm),
       TO_NUMBER(cadence_spm), TO_NUMBER(acc_peak_g), TO_NUMBER(battery_pct), phase,
       SDO_GEOMETRY(2001, 4326, SDO_POINT_TYPE(TO_NUMBER(lon), TO_NUMBER(lat), NULL), NULL, NULL)
FROM   stg_watch_stream;
COMMIT;

INSERT INTO car_stream (device_id, seq_no, event_ts, ingest_ts, lat, lon,
                        speed_kmh, heading_deg, geom)
SELECT device_id, TO_NUMBER(seq_no),
       FROM_TZ(TO_TIMESTAMP(event_ts,  'YYYY-MM-DD HH24:MI:SS'), 'Europe/Berlin'),
       FROM_TZ(TO_TIMESTAMP(ingest_ts, 'YYYY-MM-DD HH24:MI:SS'), 'Europe/Berlin'),
       TO_NUMBER(lat), TO_NUMBER(lon), TO_NUMBER(speed_kmh), TO_NUMBER(heading_deg),
       SDO_GEOMETRY(2001, 4326, SDO_POINT_TYPE(TO_NUMBER(lon), TO_NUMBER(lat), NULL), NULL, NULL)
FROM   stg_car_stream;

COMMIT;

--==============================================================================
-- 3. JSON, GeoJSON and FHIR files (chunks, then documents)
--    SQLcl LOAD does not read JSON (SET LOADFORMAT JSON applies to UNLOAD
--    only). data/_load/json_chunks.csv therefore contains all GeoJSON files,
--    Jonas' symptom report and the FHIR bundles (NDJSON, lines of up to
--    11,865 bytes) as compact JSON in chunks of at most 1000 characters
--    (generated with data/_generator/make_load_copies.py):
--      LAYER     file name without extension (trails, osm_roads, ...,
--                fhir_bundles_all_patients)
--      DOC_NO    0 = document without "features", 1..n = features;
--                for the FHIR bundles 1..n = line of the NDJSON file
--      CHUNK_NO  order of the chunks within a document
--    The delimiter is the backtick, it does not occur in the data.
--==============================================================================

PROMPT
PROMPT --- 3. Load JSON, GeoJSON and FHIR files (chunks, then documents)
SET LOADFORMAT DEFAULT
SET LOADFORMAT DELIMITED DELIMITER ` ENCLOSURES OFF COLUMN_NAMES ON ENCODING UTF8
SET LOAD DEFAULT
SET LOAD BATCH_ROWS 1000 BATCHES_PER_COMMIT 10 ERRORS 0 TRUNCATE ON UNKNOWN_COLUMNS_FAIL ON

LOAD stg_json_chunks &data_dir/_load/json_chunks.csv

-- Reassemble the chunks into documents: one pass in the order
-- LAYER, DOC_NO, CHUNK_NO; whenever a new document starts, the previous
-- one is saved as JSON.
DECLARE
  l_doc    CLOB;
  l_layer  VARCHAR2(30);
  l_doc_no NUMBER;
  l_cnt    PLS_INTEGER;

  PROCEDURE save_doc IS
  BEGIN
    IF l_layer IS NOT NULL THEN
      INSERT INTO stg_json_docs (layer, doc_no, json_document)
      VALUES (l_layer, l_doc_no, JSON(l_doc));
      DBMS_LOB.FREETEMPORARY(l_doc);
    END IF;
  END save_doc;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM stg_json_chunks;
  IF l_cnt <> &exp_json_chunks THEN
    RAISE_APPLICATION_ERROR(-20011, 'STG_JSON_CHUNKS: ' || l_cnt || ' rows, expected &exp_json_chunks');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD('STG_JSON_CHUNKS', 32) || LPAD(l_cnt, 8));

  DELETE FROM stg_json_docs;
  FOR c IN (SELECT layer,
                   TO_NUMBER(doc_no)   AS doc_no,
                   TO_NUMBER(chunk_no) AS chunk_no,
                   chunk_text
            FROM   stg_json_chunks
            ORDER  BY layer, TO_NUMBER(doc_no), TO_NUMBER(chunk_no)) LOOP
    IF l_layer IS NULL OR c.layer <> l_layer OR c.doc_no <> l_doc_no THEN
      save_doc;
      l_layer  := c.layer;
      l_doc_no := c.doc_no;
      DBMS_LOB.CREATETEMPORARY(l_doc, TRUE);
    END IF;
    DBMS_LOB.WRITEAPPEND(l_doc, LENGTH(c.chunk_text), c.chunk_text);
  END LOOP;
  save_doc;
  COMMIT;

  SELECT COUNT(*) INTO l_cnt FROM stg_json_docs;
  IF l_cnt <> &exp_json_docs THEN
    RAISE_APPLICATION_ERROR(-20011, 'STG_JSON_DOCS: ' || l_cnt || ' documents, expected &exp_json_docs');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD('STG_JSON_DOCS', 32) || LPAD(l_cnt, 8));

  SELECT COUNT(DISTINCT layer) INTO l_cnt FROM stg_json_docs;
  IF l_cnt <> &exp_json_layers THEN
    RAISE_APPLICATION_ERROR(-20011, 'STG_JSON_DOCS: ' || l_cnt || ' files, expected &exp_json_layers');
  END IF;
END;
/

-- FHIR bundles: one document per line of the NDJSON file, the first entry
-- of each bundle is the Patient resource
DECLARE
  l_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_cnt
  FROM   stg_json_docs s
  WHERE  s.layer = 'fhir_bundles_all_patients'
  AND    s.doc_no > 0
  AND    JSON_VALUE(s.json_document, '$.entry[0].resource.resourceType') = 'Patient';
  IF l_cnt <> &exp_fhir_bundles THEN
    RAISE_APPLICATION_ERROR(-20015, 'FHIR: ' || l_cnt || ' bundles with Patient, expected &exp_fhir_bundles');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD('FHIR bundles', 32) || LPAD(l_cnt, 8));
END;
/

--==============================================================================
-- 3a. to 3c. FHIR bundles: one document = one bundle of one person
--    Only symptom reports, diagnoses and medication recommendations are
--    taken over, of the person only age and gender. Name, address, date of
--    birth, previous illnesses and measurements stay in the file.
--==============================================================================

-- 3a. Symptom reports (Condition, category problem-list-item) with age and gender.
--     Reports from the health app carry their location as FHIR geolocation
--     extension (latitude, longitude); it becomes a point geometry.
INSERT INTO symptom_reports (report_id, source, reported_by, reported_on, age, gender, report_text,
                             body_site_code, body_site_text, severity, clinical_status, geom)
SELECT jt.report_id, 'fhir', jt.reported_by, TO_DATE(SUBSTR(jt.reported_on, 1, 10), 'YYYY-MM-DD'),
       TRUNC(MONTHS_BETWEEN(TO_DATE(SUBSTR(jt.bundle_ts, 1, 10), 'YYYY-MM-DD'),
                            TO_DATE(jt.birth_date, 'YYYY-MM-DD')) / 12),
       jt.gender, jt.report_text, jt.body_site_code, jt.body_site_text, jt.severity, jt.clinical_status,
       CASE WHEN jt.geo_lon IS NOT NULL AND jt.geo_lat IS NOT NULL
            THEN SDO_GEOMETRY(2001, 4326, SDO_POINT_TYPE(jt.geo_lon, jt.geo_lat, NULL), NULL, NULL) END
FROM   stg_json_docs s,
       JSON_TABLE(s.json_document, '$'
         COLUMNS (bundle_ts   VARCHAR2(40) PATH '$.timestamp',
                  gender      VARCHAR2(10) PATH '$.entry[0].resource.gender',
                  birth_date  VARCHAR2(10) PATH '$.entry[0].resource.birthDate',
                  NESTED PATH '$.entry[*].resource'
                    COLUMNS (resource_type    VARCHAR2(30)   PATH '$.resourceType',
                             category         VARCHAR2(30)   PATH '$.category[0].coding[0].code',
                             report_id        VARCHAR2(30)   PATH '$.id',
                             reported_by      VARCHAR2(60)   PATH '$.note[0].authorString',
                             reported_on      VARCHAR2(30)   PATH '$.recordedDate',
                             report_text      VARCHAR2(4000) PATH '$.note[0].text',
                             body_site_code   VARCHAR2(60)   PATH '$.bodySite[0].coding[0].code',
                             body_site_text   VARCHAR2(100)  PATH '$.bodySite[0].text',
                             severity         VARCHAR2(20)   PATH '$.severity.text',
                             clinical_status  VARCHAR2(20)   PATH '$.clinicalStatus.coding[0].code',
                             geo_lat          NUMBER         PATH '$.extension[0].extension[*]?(@.url == "latitude").valueDecimal',
                             geo_lon          NUMBER         PATH '$.extension[0].extension[*]?(@.url == "longitude").valueDecimal'))) jt
WHERE  s.layer = 'fhir_bundles_all_patients'
AND    s.doc_no > 0
AND    jt.resource_type = 'Condition'
AND    jt.category      = 'problem-list-item';
COMMIT;

-- 3b. Diagnoses (Condition, category encounter-diagnosis); evidence[0] = symptom report
INSERT INTO diagnoses (diagnosis_id, report_id, diagnosis_code, diagnosis_label, body_site_code,
                       body_site_text, verification_status, confirmed_by, clinical_status,
                       diagnosed_on, diagnosed_by)
SELECT jt.diagnosis_id, REPLACE(jt.evidence_ref, 'Condition/'), jt.diagnosis_code, jt.diagnosis_label,
       jt.body_site_code, jt.body_site_text, jt.verification_status, jt.confirmed_by, jt.clinical_status,
       TO_DATE(SUBSTR(jt.diagnosed_on, 1, 10), 'YYYY-MM-DD'), REPLACE(jt.asserter_ref, 'Organization/')
FROM   stg_json_docs s,
       JSON_TABLE(s.json_document, '$.entry[*].resource'
         COLUMNS (resource_type        VARCHAR2(30)  PATH '$.resourceType',
                  category             VARCHAR2(30)  PATH '$.category[0].coding[0].code',
                  diagnosis_id         VARCHAR2(30)  PATH '$.id',
                  evidence_ref         VARCHAR2(40)  PATH '$.evidence[0].reference.reference',
                  diagnosis_code       VARCHAR2(60)  PATH '$.code.coding[0].code',
                  diagnosis_label      VARCHAR2(100) PATH '$.code.text',
                  body_site_code       VARCHAR2(60)  PATH '$.bodySite[0].coding[0].code',
                  body_site_text       VARCHAR2(100) PATH '$.bodySite[0].text',
                  verification_status  VARCHAR2(20)  PATH '$.verificationStatus.coding[0].code',
                  confirmed_by         VARCHAR2(20)  PATH '$.evidence[1].concept.text',
                  clinical_status      VARCHAR2(20)  PATH '$.clinicalStatus.coding[0].code',
                  diagnosed_on         VARCHAR2(30)  PATH '$.recordedDate',
                  asserter_ref         VARCHAR2(40)  PATH '$.asserter.reference')) jt
WHERE  s.layer = 'fhir_bundles_all_patients'
AND    s.doc_no > 0
AND    jt.resource_type = 'Condition'
AND    jt.category      = 'encounter-diagnosis';
COMMIT;

-- 3c. Medication recommendations (MedicationRequest); reason[0] = diagnosis, reason[1] = symptom report
INSERT INTO medication_recommendations (recommendation_id, diagnosis_id, report_id, medication_code,
                                        medication_text, dosage_text, intent, status,
                                        recommended_on, recommended_by)
SELECT jt.recommendation_id, REPLACE(jt.diagnosis_ref, 'Condition/'), REPLACE(jt.report_ref, 'Condition/'),
       jt.medication_code, jt.medication_text, jt.dosage_text, jt.intent, jt.status,
       TO_DATE(SUBSTR(jt.recommended_on, 1, 10), 'YYYY-MM-DD'), REPLACE(jt.requester_ref, 'Organization/')
FROM   stg_json_docs s,
       JSON_TABLE(s.json_document, '$.entry[*].resource'
         COLUMNS (resource_type      VARCHAR2(30)  PATH '$.resourceType',
                  recommendation_id  VARCHAR2(30)  PATH '$.id',
                  diagnosis_ref      VARCHAR2(40)  PATH '$.reason[0].reference.reference',
                  report_ref         VARCHAR2(40)  PATH '$.reason[1].reference.reference',
                  medication_code    VARCHAR2(40)  PATH '$.medication.concept.coding[0].code',
                  medication_text    VARCHAR2(200) PATH '$.medication.concept.text',
                  dosage_text        VARCHAR2(200) PATH '$.dosageInstruction[0].text',
                  intent             VARCHAR2(20)  PATH '$.intent',
                  status             VARCHAR2(20)  PATH '$.status',
                  recommended_on     VARCHAR2(30)  PATH '$.authoredOn',
                  requester_ref      VARCHAR2(40)  PATH '$.requester.reference')) jt
WHERE  s.layer = 'fhir_bundles_all_patients'
AND    s.doc_no > 0
AND    jt.resource_type = 'MedicationRequest';
COMMIT;

--==============================================================================
-- 4. GeoJSON files and Jonas' app report (documents from STG_JSON_DOCS, step 3)
--==============================================================================

-- 4a. Places of the story (synthetic). One document per feature (DOC_NO > 0).
INSERT INTO trail_segments (segment_id, trail_id, trail_name, segment_name, length_m,
                            elev_from_m, elev_to_m, grade_pct, difficulty, geom)
SELECT jt.segment_id, jt.trail_id, jt.trail_name, jt.segment_name, jt.length_m,
       jt.elev_from_m, jt.elev_to_m, jt.grade_pct, jt.difficulty,
       SDO_UTIL.FROM_GEOJSON(jt.geom_json, NULL, 4326)
FROM   stg_json_docs s,
       JSON_TABLE(s.json_document, '$'
         COLUMNS (segment_id    VARCHAR2(10)  PATH '$.properties.segment_id',
                  trail_id      VARCHAR2(10)  PATH '$.properties.trail_id',
                  trail_name    VARCHAR2(60)  PATH '$.properties.trail_name',
                  segment_name  VARCHAR2(60)  PATH '$.properties.segment_name',
                  length_m      NUMBER        PATH '$.properties.length_m',
                  elev_from_m   NUMBER        PATH '$.properties.elev_from_m',
                  elev_to_m     NUMBER        PATH '$.properties.elev_to_m',
                  grade_pct     NUMBER        PATH '$.properties.grade_pct',
                  difficulty    VARCHAR2(20)  PATH '$.properties.difficulty',
                  geom_json     CLOB FORMAT JSON PATH '$.geometry')) jt
WHERE  s.layer = 'trails'
AND    s.doc_no > 0;
COMMIT;

INSERT INTO parking_lots (parking_id, name, capacity, car_access, geom)
SELECT jt.parking_id, jt.name, jt.capacity,
       CASE jt.car_access WHEN 'true' THEN TRUE WHEN 'false' THEN FALSE END,
       SDO_UTIL.FROM_GEOJSON(jt.geom_json, NULL, 4326)
FROM   stg_json_docs s,
       JSON_TABLE(s.json_document, '$'
         COLUMNS (parking_id  VARCHAR2(10)  PATH '$.properties.parking_id',
                  name        VARCHAR2(100) PATH '$.properties.name',
                  capacity    NUMBER        PATH '$.properties.capacity',
                  car_access  VARCHAR2(5)   PATH '$.properties.car_access',
                  geom_json   CLOB FORMAT JSON PATH '$.geometry')) jt
WHERE  s.layer = 'parking_lots'
AND    s.doc_no > 0;
COMMIT;

INSERT INTO pois (poi_id, name, poi_type, geom)
SELECT jt.poi_id, jt.name, jt.poi_type, SDO_UTIL.FROM_GEOJSON(jt.geom_json, NULL, 4326)
FROM   stg_json_docs s,
       JSON_TABLE(s.json_document, '$'
         COLUMNS (poi_id     VARCHAR2(10)  PATH '$.properties.poi_id',
                  name       VARCHAR2(100) PATH '$.properties.name',
                  poi_type   VARCHAR2(30)  PATH '$.properties.poi_type',
                  geom_json  CLOB FORMAT JSON PATH '$.geometry')) jt
WHERE  s.layer = 'pois'
AND    s.doc_no > 0;
COMMIT;

INSERT INTO zones (zone_id, zone_type, name, note, geom)
SELECT jt.zone_id, jt.zone_type, jt.name, jt.note, SDO_UTIL.FROM_GEOJSON(jt.geom_json, NULL, 4326)
FROM   stg_json_docs s,
       JSON_TABLE(s.json_document, '$'
         COLUMNS (zone_id    VARCHAR2(10)  PATH '$.properties.zone_id',
                  zone_type  VARCHAR2(20)  PATH '$.properties.zone_type',
                  name       VARCHAR2(100) PATH '$.properties.name',
                  note       VARCHAR2(400) PATH '$.properties.note',
                  geom_json  CLOB FORMAT JSON PATH '$.geometry')) jt
WHERE  s.layer = 'zones'
AND    s.doc_no > 0;
COMMIT;

-- 4b. OpenStreetMap: origin and attribution per file (header, DOC_NO = 0)
INSERT INTO osm_layers (layer_name, attribution, license, license_url, copyright_url,
                        source, osm_base_timestamp, downloaded_at, overpass_query)
SELECT jt.layer_name, jt.attribution, jt.license, jt.license_url, jt.copyright_url,
       jt.source,
       TO_TIMESTAMP_TZ(REPLACE(jt.osm_base_timestamp, 'Z', '+00:00'), 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
       TO_TIMESTAMP_TZ(REPLACE(jt.downloaded_at,      'Z', '+00:00'), 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
       jt.overpass_query
FROM   stg_json_docs s,
       JSON_TABLE(s.json_document, '$'
         COLUMNS (layer_name          VARCHAR2(30)   PATH '$.name',
                  attribution         VARCHAR2(200)  PATH '$.attribution',
                  license             VARCHAR2(30)   PATH '$.license',
                  license_url         VARCHAR2(200)  PATH '$.license_url',
                  copyright_url       VARCHAR2(200)  PATH '$.copyright_url',
                  source              VARCHAR2(200)  PATH '$.source',
                  osm_base_timestamp  VARCHAR2(40)   PATH '$.osm_base_timestamp',
                  downloaded_at       VARCHAR2(40)   PATH '$.downloaded_at',
                  overpass_query      VARCHAR2(4000) PATH '$.query')) jt
WHERE  s.layer LIKE 'osm\_%' ESCAPE '\'
AND    s.doc_no = 0;
COMMIT;

-- 4c. OpenStreetMap: features. Table name = LAYER (file name without extension).
DECLARE
  TYPE t_names IS TABLE OF VARCHAR2(30);
  l_layers t_names := t_names('osm_trails', 'osm_parking', 'osm_pois',
                              'osm_roads', 'osm_hospitals', 'osm_boundaries');
  l_rows     PLS_INTEGER;
  l_expected PLS_INTEGER;
BEGIN
  FOR i IN 1 .. l_layers.COUNT LOOP
    EXECUTE IMMEDIATE
      'INSERT INTO ' || DBMS_ASSERT.SIMPLE_SQL_NAME(l_layers(i)) || '
              (feature_id, osm_type, osm_id, osm_url, name, tags, geom)
       SELECT jt.feature_id, jt.osm_type, jt.osm_id, jt.osm_url, jt.name, jt.tags,
              SDO_UTIL.FROM_GEOJSON(jt.geom_json, NULL, 4326)
       FROM   stg_json_docs s,
              JSON_TABLE(s.json_document, ''$''
                COLUMNS (feature_id  VARCHAR2(40)  PATH ''$.id'',
                         osm_type    VARCHAR2(10)  PATH ''$.properties.osm_type'',
                         osm_id      NUMBER        PATH ''$.properties.osm_id'',
                         osm_url     VARCHAR2(200) PATH ''$.properties.osm_url'',
                         name        VARCHAR2(400) PATH ''$.properties.name'',
                         tags        VARCHAR2(4000) FORMAT JSON PATH ''$.properties.tags'' ERROR ON ERROR,
                         geom_json   CLOB FORMAT JSON PATH ''$.geometry'')) jt
       WHERE  s.layer = :layer
       AND    s.doc_no > 0'
      USING l_layers(i);
    l_rows := SQL%ROWCOUNT;
    COMMIT;

    SELECT COUNT(*)
    INTO   l_expected
    FROM   stg_json_docs s
    WHERE  s.layer = l_layers(i)
    AND    s.doc_no > 0;

    IF l_rows <> l_expected THEN
      RAISE_APPLICATION_ERROR(-20012, l_layers(i) || ': ' || l_rows
                                      || ' features loaded, file contains ' || l_expected);
    END IF;
    DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD(UPPER(l_layers(i)), 32) || LPAD(l_rows, 8));
  END LOOP;
END;
/

-- 4d. Clip the hiking route relations in OSM_TRAILS to the demo area.
--     Overpass returns a route relation with its complete geometry (all
--     member ways), even if only a small part of it runs through the query
--     box: the 38 routes reach up to 109 km beyond Pottenstein, only about
--     17 % of their points lie in the demo area. The ways (path segments)
--     stay as they are.
--     The area is a polygon from the DEFINEs above (SRID 4326, tolerance
--     0.05 m). Relations that do not touch the area are deleted, because
--     GEOM is NOT NULL.
DECLARE
  l_area     SDO_GEOMETRY := SDO_GEOMETRY(2003, 4326, NULL,
                               SDO_ELEM_INFO_ARRAY(1, 1003, 1),
                               SDO_ORDINATE_ARRAY(&area_min_lon, &area_min_lat,
                                                  &area_max_lon, &area_min_lat,
                                                  &area_max_lon, &area_max_lat,
                                                  &area_min_lon, &area_max_lat,
                                                  &area_min_lon, &area_min_lat));
  l_before   NUMBER;
  l_after    NUMBER;
  l_clipped  PLS_INTEGER;
  l_deleted  PLS_INTEGER;
BEGIN
  SELECT NVL(SUM(SDO_UTIL.GETNUMVERTICES(t.geom)), 0)
  INTO   l_before
  FROM   osm_trails t
  WHERE  t.osm_type = 'relation';

  DELETE FROM osm_trails t
  WHERE  t.osm_type = 'relation'
  AND    SDO_GEOM.RELATE(t.geom, 'ANYINTERACT', l_area, 0.05) = 'FALSE';
  l_deleted := SQL%ROWCOUNT;
  COMMIT;

  UPDATE osm_trails t
  SET    t.geom = SDO_GEOM.SDO_INTERSECTION(t.geom, l_area, 0.05)
  WHERE  t.osm_type = 'relation';
  l_clipped := SQL%ROWCOUNT;
  COMMIT;

  SELECT NVL(SUM(SDO_UTIL.GETNUMVERTICES(t.geom)), 0)
  INTO   l_after
  FROM   osm_trails t
  WHERE  t.osm_type = 'relation';

  DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD('OSM_TRAILS relations clipped', 32) || LPAD(l_clipped, 8)
                       || ' (' || l_before || ' -> ' || l_after || ' vertices, '
                       || l_deleted || ' outside the area deleted)');
END;
/

-- 4e. Jonas' symptom report from the app. Age and gender come from his
--     FHIR bundle in STG_JSON_DOCS (layer fhir_bundles_all_patients).
INSERT INTO symptom_reports (report_id, source, reported_by, reported_on, age, gender, report_text,
                             body_site_code, body_site_text, clinical_status, mechanism, audible_pop,
                             swelling_onset_hours, instability, locking, weight_bearing, pain_nrs, geom)
SELECT jt.report_id, 'app', jt.channel,
       CAST(TO_TIMESTAMP_TZ(jt.created_ts, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM') AS DATE),
       TRUNC(MONTHS_BETWEEN(TO_DATE(SUBSTR(jt.created_ts, 1, 10), 'YYYY-MM-DD'),
                            TO_DATE(p.birth_date, 'YYYY-MM-DD')) / 12),
       p.gender, jt.free_text,
       jt.body_region || NVL2(jt.side, '_' || jt.side, NULL),
       INITCAP(jt.body_region) || NVL2(jt.side, ' ' || jt.side, NULL),
       'active', jt.mechanism,
       CASE jt.audible_pop WHEN 'true' THEN TRUE WHEN 'false' THEN FALSE END,
       jt.swelling_onset_hours,
       CASE jt.instability WHEN 'true' THEN TRUE WHEN 'false' THEN FALSE END,
       CASE jt.locking     WHEN 'true' THEN TRUE WHEN 'false' THEN FALSE END,
       jt.weight_bearing, jt.pain_nrs,
       SDO_UTIL.FROM_GEOJSON(jt.location_json, NULL, 4326)
FROM   stg_json_docs f,
       JSON_TABLE(f.json_document, '$'
         COLUMNS (report_id             VARCHAR2(30)   PATH '$.report_id',
                  patient_id            VARCHAR2(10)   PATH '$.patient_id',
                  created_ts            VARCHAR2(40)   PATH '$.created_ts',
                  channel               VARCHAR2(60)   PATH '$.channel',
                  free_text             VARCHAR2(4000) PATH '$.free_text',
                  body_region           VARCHAR2(30)   PATH '$.structured_answers.body_region',
                  side                  VARCHAR2(10)   PATH '$.structured_answers.side',
                  mechanism             VARCHAR2(30)   PATH '$.structured_answers.mechanism',
                  audible_pop           VARCHAR2(5)    PATH '$.structured_answers.audible_pop',
                  swelling_onset_hours  NUMBER         PATH '$.structured_answers.swelling_onset_hours',
                  instability           VARCHAR2(5)    PATH '$.structured_answers.instability',
                  locking               VARCHAR2(5)    PATH '$.structured_answers.locking',
                  weight_bearing        VARCHAR2(30)   PATH '$.structured_answers.weight_bearing',
                  pain_nrs              NUMBER         PATH '$.structured_answers.pain_nrs',
                  location_json         CLOB FORMAT JSON PATH '$.location')) jt
JOIN   (SELECT JSON_VALUE(b.json_document, '$.entry[0].resource.id')        AS patient_id,
               JSON_VALUE(b.json_document, '$.entry[0].resource.gender')    AS gender,
               JSON_VALUE(b.json_document, '$.entry[0].resource.birthDate') AS birth_date
        FROM   stg_json_docs b
        WHERE  b.layer = 'fhir_bundles_all_patients'
        AND    b.doc_no > 0) p
ON     p.patient_id = jt.patient_id
WHERE  f.layer = 'symptom_report_jonas'
AND    f.doc_no = 0;

COMMIT;

DECLARE
  TYPE t_check IS RECORD (table_name VARCHAR2(128), expected PLS_INTEGER);
  TYPE t_checks IS TABLE OF t_check;
  l_checks t_checks := t_checks(
    t_check('SYMPTOM_REPORTS',            &exp_symptom_reports),
    t_check('DIAGNOSES',                  &exp_diagnoses),
    t_check('MEDICATION_RECOMMENDATIONS', &exp_medication_recs));
  l_cnt PLS_INTEGER;
BEGIN
  FOR i IN 1 .. l_checks.COUNT LOOP
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || l_checks(i).table_name INTO l_cnt;
    IF l_cnt <> l_checks(i).expected THEN
      RAISE_APPLICATION_ERROR(-20016, l_checks(i).table_name || ': ' || l_cnt
                                      || ' rows, expected ' || l_checks(i).expected);
    END IF;
    DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD(l_checks(i).table_name, 32) || LPAD(l_cnt, 8));
  END LOOP;
END;
/

-- Staging contents are no longer needed
TRUNCATE TABLE stg_json_chunks;

--==============================================================================
-- 5. Statistics
--==============================================================================

PROMPT
PROMPT --- 5. Statistics
BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, cascade => TRUE);
END;
/

--==============================================================================
-- 6. Overview
--==============================================================================

PROMPT
PROMPT --- 6. Rows per table
SELECT table_name, num_rows
FROM   user_tables
WHERE  table_name NOT LIKE 'RDF\_NETWORK#%' ESCAPE '\'
AND    table_name NOT LIKE 'STG\_%'      ESCAPE '\'
ORDER  BY table_name;

PROMPT --- OSM attribution (belongs on every map)
SELECT layer_name, attribution, license, osm_base_timestamp
FROM   osm_layers
ORDER  BY layer_name;

PROMPT
PROMPT Done. Continue with 04_create_annotations.sql (spatial indexes: 07, RDF: 08, 09a and 09b).

SPOOL OFF
