--------------------------------------------------------------------------------
-- File       : 04_create_annotations.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Adds schema annotations (23ai and later) to all tables from
--              02_create_tables.sql and their columns. Annotations are
--              name-value pairs that tools, Select AI and humans can read
--              (USER_ANNOTATIONS_USAGE).
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as the demo user, after 02 (before or after 03)
--                sql doag2026@<tns_alias> @04_create_annotations.sql
-- Re-runnable: yes. Step 1 first removes all existing annotations in the
--              schema, step 2 creates them again.
-- Encoding   : UTF-8 (the copyright sign and German data values such as
--              Röntgen in the values). Start SQLcl with
--              JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8 (README.md).
-- Language   : Annotation values are English. Coded values that occur in
--              the (German) data are quoted as they are, with the English
--              meaning in parentheses, e.g. frei (free).
-- Log        : logs/sql/04_create_annotations.log in the project folder,
--              overwritten on every run
--
-- Annotations
--   Tables  : Display, Description, Source, License, Feature, Demo_Step
--   Columns : Display, Description, Unit (only where a unit applies)
--------------------------------------------------------------------------------

SET DEFINE OFF
SET FEEDBACK OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/04_create_annotations.log

PROMPT
PROMPT === 04 Annotations for tables and columns ===

BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the demo user, not as ADMIN.');
  END IF;
END;
/

--------------------------------------------------------------------------------
-- 1. Remove all existing annotations
--    Based on USER_ANNOTATIONS_USAGE: one ALTER ... ANNOTATIONS (DROP ...)
--    per object (table, view, materialized view, index) and per column of
--    a table.
--    Excluded are:
--      - annotations inherited from a domain (DOMAIN_NAME set); they can
--        only be changed on the domain
--      - the objects of the RDF network (RDF_NETWORK#...), they belong to
--        Oracle
--      - STG_RDF_TRIPLES: 08_create_rdf_network.sql sets its annotations
--        when creating it, this script does not set them again
--      - GEOMETRY_ERRORS: likewise, set by 07_create_spatial_indexes.sql
--    Columns of views cannot be changed afterwards (only with
--    CREATE OR REPLACE VIEW); they show up as WARNING.
--------------------------------------------------------------------------------

PROMPT
PROMPT --- 1. Remove existing annotations
DECLARE
  l_sql    VARCHAR2(1000);
  l_cnt    PLS_INTEGER := 0;
  l_warn   PLS_INTEGER := 0;
BEGIN
  FOR a IN (SELECT object_name, object_type, column_name, annotation_name
            FROM   user_annotations_usage
            WHERE  domain_name IS NULL
            AND    object_type IN ('TABLE', 'VIEW', 'MATERIALIZED VIEW', 'INDEX')
            AND    object_name NOT LIKE 'RDF\_NETWORK#%' ESCAPE '\'
            AND    object_name NOT IN ('STG_RDF_TRIPLES', 'GEOMETRY_ERRORS')
            ORDER  BY object_type, object_name, column_name NULLS FIRST, annotation_name) LOOP
    l_sql := 'ALTER ' || a.object_type || ' ' || DBMS_ASSERT.ENQUOTE_NAME(a.object_name, FALSE)
             || CASE WHEN a.column_name IS NULL
                     THEN ' ANNOTATIONS (DROP ' || DBMS_ASSERT.ENQUOTE_NAME(a.annotation_name, FALSE) || ')'
                     ELSE ' MODIFY (' || DBMS_ASSERT.ENQUOTE_NAME(a.column_name, FALSE)
                          || ' ANNOTATIONS (DROP ' || DBMS_ASSERT.ENQUOTE_NAME(a.annotation_name, FALSE) || '))'
                END;
    BEGIN
      EXECUTE IMMEDIATE l_sql;
      l_cnt := l_cnt + 1;
    EXCEPTION
      WHEN OTHERS THEN
        l_warn := l_warn + 1;
        DBMS_OUTPUT.PUT_LINE('WARNING ' || l_sql || ' -> ' || SQLERRM);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('OK      ' || l_cnt || ' annotations removed, ' || l_warn || ' warnings');
END;
/

--------------------------------------------------------------------------------
-- 2. Set annotations for tables and columns
--------------------------------------------------------------------------------

PROMPT
PROMPT --- 2. Set annotations
DECLARE
  TYPE t_list IS TABLE OF VARCHAR2(1000);

  ------------------------------------------------------------------------------
  -- Tables: TABLE|Display|Description|Source|License|Feature|Demo_Step
  ------------------------------------------------------------------------------
  l_tables t_list := t_list(
    'ROAD_NODES|Road nodes|Nodes of the simplified road network between Pottenstein and Nuremberg|data/spatial/road_nodes.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|Spatial|6 (fallback for routing)',
    'ROAD_LINKS|Road links|Links of the simplified road network with travel time|data/spatial/road_links.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|Spatial|6 (fallback for routing)',
    'PROVIDERS|Care providers|GP practices, specialist practices, radiology centres, hospitals and physiotherapy in the care network, fictitious|data/graph/providers.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|SQL Property Graph, Spatial|5, 6',
    'DEVICES|Devices|MRI and X-ray devices of the care providers|data/graph/devices.csv|CC0 (synthetic)|SQL Property Graph|5',
    'PATIENTS|Persons|Persons in the care network, P0001 is Jonas|data/graph/patients.csv|CC0 (synthetic)|SQL Property Graph|5',
    'APPOINTMENT_SLOTS|Appointments|Consultation and MRI appointments, free or booked|data/graph/appointment_slots.csv|CC0 (synthetic)|SQL Property Graph|5',
    'PROVIDER_RELATIONS|Relations between care providers|Referrals, cooperations and teleradiology|data/graph/provider_relations.csv|CC0 (synthetic)|SQL Property Graph|5',
    'PATIENT_PROVIDER_RELATIONS|Relations person to care provider|GP relations and earlier treatment relations|data/graph/patient_provider_relations.csv|CC0 (synthetic)|SQL Property Graph|5',
    'CASE_NOTES|Case library|290 German case notes on knee and ankle with confirmed diagnosis|data/casebase/case_notes.csv|CC0 (synthetic)|Oracle Text, AI Vector Search|3',
    'WATCH_STREAM|Watch stream|Fitness watch of Jonas, one measurement every 5 s, complete recording of 16.11.2026|data/stream/watch_stream_jonas.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|Spatial, Streaming|2',
    'CAR_STREAM|Car stream|Car of the friend, one measurement every 10 s, drive to the hiking car park|data/stream/car_stream_friend.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|Spatial, Streaming|6',
    'TRAIL_SEGMENTS|Trail segments|Felsenpfad loop trail of the story and neighbouring trails on real OSM paths (fictitious names), elevation and grade per segment|data/spatial/trails.geojson|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|Spatial|2',
    'PARKING_LOTS|Parking lots of the story|Parking lots of the story at real OSM parking lots (fictitious names), car_access shows whether they can be reached by car|data/spatial/parking_lots.geojson|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|Spatial|6',
    'POIS|Places of the story|Shelter hut, viewpoint and trail junction of the story at a real OSM shelter, viewpoint and path junction (fictitious names)|data/spatial/pois.geojson|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|Spatial|2',
    'ZONES|Zones|Dead zone and geofences of the parking lots reachable by car|data/spatial/zones.geojson|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|Spatial, Streaming|2, 6',
    'OSM_LAYERS|OSM datasets|Origin, license and attribution of the OSM extracts|data/spatial/osm_*.geojson|ODbL 1.0, © OpenStreetMap contributors|Spatial|all maps',
    'OSM_TRAILS|OSM paths|Paths and hiking routes around Pottenstein from OpenStreetMap; route relations clipped to the demo area (lon 11.370-11.460, lat 49.755-49.795)|data/spatial/osm_trails.geojson|ODbL 1.0, © OpenStreetMap contributors|Spatial|2 (map)',
    'OSM_PARKING|OSM parking|Parking lots around Pottenstein from OpenStreetMap|data/spatial/osm_parking.geojson|ODbL 1.0, © OpenStreetMap contributors|Spatial|map',
    'OSM_POIS|OSM POIs|Shelter huts, viewpoints and signposts around Pottenstein from OpenStreetMap|data/spatial/osm_pois.geojson|ODbL 1.0, © OpenStreetMap contributors|Spatial|map',
    'OSM_ROADS|OSM roads|Motorways down to state roads between Nuremberg, Pottenstein and Bayreuth from OpenStreetMap|data/spatial/osm_roads.geojson|ODbL 1.0, © OpenStreetMap contributors|Spatial|6 (map)',
    'OSM_HOSPITALS|OSM hospitals|Hospitals as points from OpenStreetMap, emergency department in tag emergency|data/spatial/osm_hospitals.geojson|ODbL 1.0, © OpenStreetMap contributors|Spatial, JSON|6 (plan B)',
    'OSM_BOUNDARIES|OSM city boundaries|City boundaries of Nuremberg and Fuerth from OpenStreetMap|data/spatial/osm_boundaries.geojson|ODbL 1.0, © OpenStreetMap contributors|Spatial, SQL Property Graph|5',
    'SYMPTOM_REPORTS|Symptom reports|Symptoms in own words: 1,458 reports from the FHIR bundles and Jonas'' app report; of the person only age and gender|data/json/fhir_bundles_all_patients.ndjson, data/json/symptom_report_jonas.json|CC0 (synthetic)|JSON (split into relational rows), AI Vector Search, Oracle Text, Spatial|1, 3',
    'DIAGNOSES|Diagnoses|Diagnoses for the symptom reports; knee codes as in CASE_NOTES and in the knee graph|data/json/fhir_bundles_all_patients.ndjson|CC0 (synthetic)|JSON (split into relational rows)|3',
    'MEDICATION_RECOMMENDATIONS|Medication recommendations|Recommended or prescribed medications per diagnosis and symptom report, fictitious, no therapy recommendation|data/json/fhir_bundles_all_patients.ndjson|CC0 (synthetic)|JSON (split into relational rows)|3, 7',
    -- Staging tables of the loader
    'STG_ROAD_NODES|Staging road_nodes|Text columns as in the CSV file, only for 03_load_data.sql|data/spatial/road_nodes.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|SQLcl LOAD|',
    'STG_ROAD_LINKS|Staging road_links|Text columns as in the CSV file, only for 03_load_data.sql|data/spatial/road_links.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|SQLcl LOAD|',
    'STG_PROVIDERS|Staging providers|Text columns as in the CSV file, only for 03_load_data.sql|data/graph/providers.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|SQLcl LOAD|',
    'STG_DEVICES|Staging devices|Text columns as in the CSV file, only for 03_load_data.sql|data/graph/devices.csv|CC0 (synthetic)|SQLcl LOAD|',
    'STG_PATIENTS|Staging patients|Text columns as in the CSV file, only for 03_load_data.sql|data/graph/patients.csv|CC0 (synthetic)|SQLcl LOAD|',
    'STG_APPOINTMENT_SLOTS|Staging appointment_slots|Text columns as in the CSV file, only for 03_load_data.sql|data/graph/appointment_slots.csv|CC0 (synthetic)|SQLcl LOAD|',
    'STG_PROVIDER_RELATIONS|Staging provider_relations|Text columns as in the CSV file, only for 03_load_data.sql|data/graph/provider_relations.csv|CC0 (synthetic)|SQLcl LOAD|',
    'STG_PATIENT_PROVIDER_RELATIONS|Staging patient_provider_relations|Text columns as in the CSV file, only for 03_load_data.sql|data/graph/patient_provider_relations.csv|CC0 (synthetic)|SQLcl LOAD|',
    'STG_CASE_NOTES|Staging case_notes|Text columns as in the CSV file, only for 03_load_data.sql|data/casebase/case_notes.csv|CC0 (synthetic)|SQLcl LOAD|',
    'STG_WATCH_STREAM|Staging watch_stream|Text columns as in the CSV file, only for 03_load_data.sql|data/stream/watch_stream_jonas.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|SQLcl LOAD|',
    'STG_CAR_STREAM|Staging car_stream|Text columns as in the CSV file, only for 03_load_data.sql|data/stream/car_stream_friend.csv|ODbL 1.0, © OpenStreetMap contributors (synthetic story data on OSM geometry)|SQLcl LOAD|',
    'STG_TEXT_LINES|Staging text lines|One line per record from N-Triples files, only for 09a_load_knee_kg.sql and 09b_load_fma.sql|data/_load/knee_kg_nt.csv, data/_load/fma_nt.csv (load copies of data/rdf/*.nt)||SQLcl LOAD|',
    'STG_JSON_CHUNKS|Staging JSON chunks|JSON, GeoJSON and NDJSON documents in chunks of at most 1000 characters, only for 03_load_data.sql|data/_load/json_chunks.csv||SQLcl LOAD|',
    'STG_JSON_DOCS|Staging JSON documents|Documents reassembled from STG_JSON_CHUNKS: DOC_NO 0 = file header, 1..n = features or NDJSON lines (FHIR bundles); only for 03_load_data.sql|data/spatial/*.geojson, data/json/symptom_report_jonas.json, data/json/fhir_bundles_all_patients.ndjson||JSON|'
  );

  ------------------------------------------------------------------------------
  -- Columns: TABLE|COLUMN|Display|Description|Unit
  -- The columns of the six OSM tables follow further down in a loop.
  ------------------------------------------------------------------------------
  l_columns t_list := t_list(
    'ROAD_NODES|NODE_ID|Node ID|Key of the road node|',
    'ROAD_NODES|NAME|Name|Place or junction|',
    'ROAD_NODES|LAT|Latitude|Geographic latitude, WGS 84|degrees',
    'ROAD_NODES|LON|Longitude|Geographic longitude, WGS 84|degrees',
    'ROAD_NODES|GEOM|Geometry|Point, SRID 4326|',

    'ROAD_LINKS|LINK_ID|Link ID|Key of the road link|',
    'ROAD_LINKS|START_NODE_ID|Start node|Foreign key to ROAD_NODES|',
    'ROAD_LINKS|END_NODE_ID|End node|Foreign key to ROAD_NODES|',
    'ROAD_LINKS|ROAD_CLASS|Road class|Autobahn (motorway), Bundesstraße (federal road), Staatsstraße (state road), Gemeindestraße (municipal road) or Stadtstraße (city road)|',
    'ROAD_LINKS|SPEED_KMH|Speed|Assumed average speed|km/h',
    'ROAD_LINKS|LENGTH_M|Length|Length of the link|m',
    'ROAD_LINKS|COST_S|Travel time|Travel time for the link|s',
    'ROAD_LINKS|DIRECTION|Direction|beide (both) = passable in both directions|',

    'PROVIDERS|PROVIDER_ID|Care provider ID|Key, e.g. PR10|',
    'PROVIDERS|NAME|Name|Name of the practice or facility, fictitious|',
    'PROVIDERS|PROVIDER_TYPE|Type|Hausarztpraxis (GP practice), Facharztpraxis (specialist practice), Radiologie (radiology), Klinik (hospital), Physiotherapie (physiotherapy)|',
    'PROVIDERS|SPECIALTY|Specialty|Medical specialty of the facility|',
    'PROVIDERS|CITY|City|City of the facility|',
    'PROVIDERS|LAT|Latitude|Geographic latitude, WGS 84|degrees',
    'PROVIDERS|LON|Longitude|Geographic longitude, WGS 84|degrees',
    'PROVIDERS|NEAREST_ROAD_NODE_ID|Nearest road node|Foreign key to ROAD_NODES, for the fallback routing|',
    'PROVIDERS|ACCEPTS_ACUTE|Accepts acute cases|TRUE if the facility accepts acute cases on the same day|',
    'PROVIDERS|GEOM|Geometry|Point, SRID 4326|',

    'DEVICES|DEVICE_ID|Device ID|Key, e.g. MRT01|',
    'DEVICES|PROVIDER_ID|Operator|Foreign key to PROVIDERS|',
    'DEVICES|MODALITY|Modality|MRT (MRI) or Röntgen (X-ray)|',
    'DEVICES|FIELD_STRENGTH_T|Field strength|Magnetic field strength of the MRI|T',
    'DEVICES|DESIGN|Design|offen (open) or geschlossen (closed), MRI only|',

    'PATIENTS|PATIENT_ID|Person ID|Key, P0001 is Jonas|',
    'PATIENTS|FIRST_NAME|First name|First name, fictitious|',
    'PATIENTS|LAST_INITIAL|Initial|First letter of the last name|',
    'PATIENTS|BIRTH_YEAR|Year of birth|Year of birth|',
    'PATIENTS|SEX|Sex|w (female) or m (male)|',
    'PATIENTS|HOME_CITY|Home town|Home town|',
    'PATIENTS|INSURANCE|Insurance|GKV (statutory) or PKV (private)|',
    'PATIENTS|GP_PROVIDER_ID|GP|Foreign key to PROVIDERS|',

    'APPOINTMENT_SLOTS|SLOT_ID|Appointment ID|Key of the appointment|',
    'APPOINTMENT_SLOTS|PROVIDER_ID|Care provider|Foreign key to PROVIDERS|',
    'APPOINTMENT_SLOTS|DEVICE_ID|Device|Foreign key to DEVICES, MRI appointments only|',
    'APPOINTMENT_SLOTS|SLOT_START|Start|Start of the appointment, Europe/Berlin|',
    'APPOINTMENT_SLOTS|DURATION_MIN|Duration|Duration of the appointment|min',
    'APPOINTMENT_SLOTS|SLOT_TYPE|Appointment type|Sprechstunde (consultation) or MRT Knie (knee MRI)|',
    'APPOINTMENT_SLOTS|STATUS|Status|frei (free) or belegt (booked)|',

    'PROVIDER_RELATIONS|RELATION_ID|Relation ID|Key of the relation|',
    'PROVIDER_RELATIONS|SRC_PROVIDER_ID|From|Foreign key to PROVIDERS, source of the edge|',
    'PROVIDER_RELATIONS|DST_PROVIDER_ID|To|Foreign key to PROVIDERS, target of the edge|',
    'PROVIDER_RELATIONS|RELATION_TYPE|Relation type|ueberweist_an (refers to), kooperiert_mit (cooperates with) or teleradiologie (teleradiology)|',

    'PATIENT_PROVIDER_RELATIONS|RELATION_ID|Relation ID|Key of the relation|',
    'PATIENT_PROVIDER_RELATIONS|PATIENT_ID|Person|Foreign key to PATIENTS|',
    'PATIENT_PROVIDER_RELATIONS|PROVIDER_ID|Care provider|Foreign key to PROVIDERS|',
    'PATIENT_PROVIDER_RELATIONS|RELATION_TYPE|Relation type|hat_hausarzt (has GP) or war_in_behandlung (was treated by)|',
    'PATIENT_PROVIDER_RELATIONS|SINCE|Since|Start of the relation|',

    'CASE_NOTES|CASE_ID|Case ID|Key of the case note|',
    'CASE_NOTES|RECORDED_ON|Date|Date of the note|',
    'CASE_NOTES|AGE|Age|Age of the person|years',
    'CASE_NOTES|SEX|Sex|w (female) or m (male)|',
    'CASE_NOTES|BODY_REGION|Body region|knie (knee) or sprunggelenk (ankle)|',
    'CASE_NOTES|SIDE|Side|rechts (right) or links (left)|',
    'CASE_NOTES|NOTE_TEXT|Case note|Free text in German, basis for full-text and vector search|',
    'CASE_NOTES|DIAGNOSIS_CODE|Diagnosis code|Code of the confirmed diagnosis, links to kg:caseDiagnosisCode in the knee graph|',
    'CASE_NOTES|DIAGNOSIS_LABEL|Diagnosis|Label of the confirmed diagnosis (German)|',
    'CASE_NOTES|CONFIRMED_BY|Confirmed by|klinisch (clinical exam), MRT (MRI) or Röntgen (X-ray)|',

    'WATCH_STREAM|DEVICE_ID|Device|Identifier of the watch|',
    'WATCH_STREAM|SEQ_NO|Sequence number|Order of the measurement on the device|',
    'WATCH_STREAM|PATIENT_ID|Person|Foreign key to PATIENTS|',
    'WATCH_STREAM|EVENT_TS|Measurement time|Event time of the measurement, Europe/Berlin; analyses use this time|',
    'WATCH_STREAM|INGEST_TS|Arrival time|Time at which the point arrived in the database|',
    'WATCH_STREAM|BUFFERED|Buffered|TRUE if the watch buffered the point in the dead zone and sent it later|',
    'WATCH_STREAM|LAT|Latitude|Geographic latitude, WGS 84|degrees',
    'WATCH_STREAM|LON|Longitude|Geographic longitude, WGS 84|degrees',
    'WATCH_STREAM|ELE_M|Elevation|Elevation above sea level|m',
    'WATCH_STREAM|HR_BPM|Pulse|Heart rate|1/min',
    'WATCH_STREAM|CADENCE_SPM|Cadence|Steps per minute|steps/min',
    'WATCH_STREAM|ACC_PEAK_G|Acceleration peak|Highest acceleration in the measurement interval|g',
    'WATCH_STREAM|BATTERY_PCT|Battery|Charge level of the watch|%',
    'WATCH_STREAM|PHASE|Phase (ground truth)|wandern (hiking), sturz (fall), stillstand (standstill), humpeln (limping), warten (waiting); for checking only, not for detection|',
    'WATCH_STREAM|GEOM|Geometry|Point, SRID 4326|',

    'CAR_STREAM|DEVICE_ID|Device|Identifier of the vehicle|',
    'CAR_STREAM|SEQ_NO|Sequence number|Order of the measurement|',
    'CAR_STREAM|EVENT_TS|Measurement time|Event time of the measurement, Europe/Berlin|',
    'CAR_STREAM|INGEST_TS|Arrival time|Time at which the point arrived in the database|',
    'CAR_STREAM|LAT|Latitude|Geographic latitude, WGS 84|degrees',
    'CAR_STREAM|LON|Longitude|Geographic longitude, WGS 84|degrees',
    'CAR_STREAM|SPEED_KMH|Speed|Current speed|km/h',
    'CAR_STREAM|HEADING_DEG|Heading|Direction, 0 = north, clockwise|degrees',
    'CAR_STREAM|GEOM|Geometry|Point, SRID 4326|',

    'TRAIL_SEGMENTS|SEGMENT_ID|Segment ID|Key, e.g. T1-S08|',
    'TRAIL_SEGMENTS|TRAIL_ID|Trail ID|T1 = Felsenpfad loop trail|',
    'TRAIL_SEGMENTS|TRAIL_NAME|Trail name|Name of the hiking trail, fictitious|',
    'TRAIL_SEGMENTS|SEGMENT_NAME|Segment name|Name of the section (German), e.g. Abstieg Felsstufe (descent over a rock step)|',
    'TRAIL_SEGMENTS|LENGTH_M|Length|Length of the segment|m',
    'TRAIL_SEGMENTS|ELEV_FROM_M|Elevation start|Elevation at the start of the segment|m',
    'TRAIL_SEGMENTS|ELEV_TO_M|Elevation end|Elevation at the end of the segment|m',
    'TRAIL_SEGMENTS|GRADE_PCT|Grade|Average grade, negative = downhill|%',
    'TRAIL_SEGMENTS|DIFFICULTY|Difficulty|leicht (easy), mittel (moderate) or schwer (difficult)|',
    'TRAIL_SEGMENTS|GEOM|Geometry|Line, SRID 4326|',

    'PARKING_LOTS|PARKING_ID|Parking lot ID|Key, PK03 is the pick-up point|',
    'PARKING_LOTS|NAME|Name|Name of the parking lot, fictitious|',
    'PARKING_LOTS|CAPACITY|Spaces|Number of parking spaces|spaces',
    'PARKING_LOTS|CAR_ACCESS|Reachable by car|FALSE for the Felsenkanzel parking lot|',
    'PARKING_LOTS|GEOM|Geometry|Point, SRID 4326|',

    'POIS|POI_ID|Place ID|Key of the place|',
    'POIS|NAME|Name|Name of the place, fictitious|',
    'POIS|POI_TYPE|Type|Schutzhütte (shelter hut), Aussichtspunkt (viewpoint) or Wegkreuzung (trail junction)|',
    'POIS|GEOM|Geometry|Point, SRID 4326|',

    'ZONES|ZONE_ID|Zone ID|Key, Z01 is the dead zone|',
    'ZONES|ZONE_TYPE|Type|Funkloch (dead zone) or Geofence Parkplatz (parking lot geofence)|',
    'ZONES|NAME|Name|Name of the zone|',
    'ZONES|NOTE|Note|Explanation of the zone|',
    'ZONES|GEOM|Geometry|Polygon, SRID 4326|',

    'OSM_LAYERS|LAYER_NAME|Dataset|Table name of the OSM extract, e.g. osm_roads|',
    'OSM_LAYERS|ATTRIBUTION|Attribution|Required on every map: © OpenStreetMap contributors|',
    'OSM_LAYERS|LICENSE|License|ODbL 1.0|',
    'OSM_LAYERS|LICENSE_URL|License URL|Text of the Open Database License|',
    'OSM_LAYERS|COPYRIGHT_URL|Copyright URL|https://www.openstreetmap.org/copyright|',
    'OSM_LAYERS|SOURCE|Source|Overpass API endpoint|',
    'OSM_LAYERS|OSM_BASE_TIMESTAMP|OSM data timestamp|Timestamp of the OpenStreetMap data at download time|',
    'OSM_LAYERS|DOWNLOADED_AT|Downloaded at|Time of the download|',
    'OSM_LAYERS|OVERPASS_QUERY|Overpass query|Query text used to download the extract|',

    'SYMPTOM_REPORTS|REPORT_ID|Report ID|FHIR Condition.id (e.g. P0002-B1) or report_id of the app|',
    'SYMPTOM_REPORTS|SOURCE|Source|fhir = from the FHIR bundles, app = Jonas'' report from the health app|',
    'SYMPTOM_REPORTS|REPORTED_BY|Reported via|Patient:in (Gesundheits-App) (patient via health app), Gesundheits-App (health app) or Hausarztpraxis (GP practice)|',
    'SYMPTOM_REPORTS|REPORTED_ON|Reported on|Date of the report|',
    'SYMPTOM_REPORTS|AGE|Age|Age on the day of the story, calculated from the date of birth; the date of birth itself is not stored|years',
    'SYMPTOM_REPORTS|GENDER|Gender|female or male|',
    'SYMPTOM_REPORTS|REPORT_TEXT|Symptom description|Free text in own words (German), basis for full-text and vector search|',
    'SYMPTOM_REPORTS|BODY_SITE_CODE|Body site (code)|Region and side, e.g. untere_extremitaet_rechts (right lower limb)|',
    'SYMPTOM_REPORTS|BODY_SITE_TEXT|Body site|Region and side as text (German)|',
    'SYMPTOM_REPORTS|SEVERITY|Severity|leicht (mild), mittel (moderate) or schwer (severe)|',
    'SYMPTOM_REPORTS|CLINICAL_STATUS|Status|active, recurrence or resolved|',
    'SYMPTOM_REPORTS|MECHANISM|Injury mechanism|App only: e.g. verdrehtrauma (twisting injury)|',
    'SYMPTOM_REPORTS|AUDIBLE_POP|Audible pop|App only|',
    'SYMPTOM_REPORTS|SWELLING_ONSET_HOURS|Swelling after|App only: time until swelling started|h',
    'SYMPTOM_REPORTS|INSTABILITY|Instability|App only|',
    'SYMPTOM_REPORTS|LOCKING|Locking|App only|',
    'SYMPTOM_REPORTS|WEIGHT_BEARING|Weight bearing|App only: e.g. eingeschränkt (limited)|',
    'SYMPTOM_REPORTS|PAIN_NRS|Pain|App only: numeric rating scale 0 to 10|NRS',
    'SYMPTOM_REPORTS|GEOM|Location|App only: point of the report, SRID 4326|',
    'SYMPTOM_REPORTS|REPORT_EMBEDDING|Embedding|Vector of REPORT_TEXT, generated with VECTOR_EMBEDDING and the ONNX model of the demo|',

    'DIAGNOSES|DIAGNOSIS_ID|Diagnosis ID|FHIR Condition.id, e.g. P0002-D1|',
    'DIAGNOSES|REPORT_ID|Symptom report|Foreign key to SYMPTOM_REPORTS (Condition.evidence)|',
    'DIAGNOSES|DIAGNOSIS_CODE|Diagnosis code|Own CodeSystem; knee codes as diagnosis_code in CASE_NOTES|',
    'DIAGNOSES|DIAGNOSIS_LABEL|Diagnosis|Label of the diagnosis (German)|',
    'DIAGNOSES|BODY_SITE_CODE|Body site (code)|Affected structure and side, e.g. knie_rechts (right knee)|',
    'DIAGNOSES|BODY_SITE_TEXT|Body site|Affected structure and side as text (German)|',
    'DIAGNOSES|VERIFICATION_STATUS|Certainty|confirmed or provisional (suspected)|',
    'DIAGNOSES|CONFIRMED_BY|Confirmed by|klinisch (clinical exam), MRT (MRI), Röntgen (X-ray), Labor (lab) or EKG (ECG)|',
    'DIAGNOSES|CLINICAL_STATUS|Status|active, recurrence or resolved|',
    'DIAGNOSES|DIAGNOSED_ON|Diagnosed on|Condition.recordedDate|',
    'DIAGNOSES|DIAGNOSED_BY|Diagnosed by|Foreign key to PROVIDERS (GP or orthopaedics)|',

    'MEDICATION_RECOMMENDATIONS|RECOMMENDATION_ID|Recommendation ID|FHIR MedicationRequest.id|',
    'MEDICATION_RECOMMENDATIONS|DIAGNOSIS_ID|Diagnosis|Foreign key to DIAGNOSES|',
    'MEDICATION_RECOMMENDATIONS|REPORT_ID|Symptom report|Foreign key to SYMPTOM_REPORTS|',
    'MEDICATION_RECOMMENDATIONS|MEDICATION_CODE|Medication (code)|Own CodeSystem, e.g. ibuprofen_400|',
    'MEDICATION_RECOMMENDATIONS|MEDICATION_TEXT|Medication|Active ingredient, strength and dosage form (German)|',
    'MEDICATION_RECOMMENDATIONS|DOSAGE_TEXT|Intake note|Fictitious note for the demo (German), no dosage recommendation|',
    'MEDICATION_RECOMMENDATIONS|INTENT|Type|proposal = recommendation, order = prescription|',
    'MEDICATION_RECOMMENDATIONS|STATUS|Status|active or completed|',
    'MEDICATION_RECOMMENDATIONS|RECOMMENDED_ON|Recommended on|MedicationRequest.authoredOn|',
    'MEDICATION_RECOMMENDATIONS|RECOMMENDED_BY|Recommended by|Foreign key to PROVIDERS|',

    'STG_TEXT_LINES|LINE_TEXT|Text line|One line of the source file|',
    'STG_JSON_CHUNKS|LAYER|File|File name without extension, e.g. trails, osm_roads, symptom_report_jonas, fhir_bundles_all_patients|',
    'STG_JSON_CHUNKS|DOC_NO|Document|0 = file header or complete document, 1..n = features or NDJSON lines|',
    'STG_JSON_CHUNKS|CHUNK_NO|Chunk|Order of the chunks within a document|',
    'STG_JSON_CHUNKS|CHUNK_TEXT|JSON chunk|Compact JSON, at most 1000 characters|',
    'STG_JSON_DOCS|LAYER|File|File name without extension, e.g. trails, osm_roads, symptom_report_jonas, fhir_bundles_all_patients|',
    'STG_JSON_DOCS|DOC_NO|Document|0 = file header or complete document, 1..n = features or NDJSON lines|',
    'STG_JSON_DOCS|JSON_DOCUMENT|JSON document|Reassembled from the chunks|'
    -- STG_RDF_TRIPLES is annotated by 08_create_rdf_network.sql when it is created
  );

  -- Columns of the six OSM tables (same structure)
  l_osm_tables t_list := t_list('OSM_TRAILS', 'OSM_PARKING', 'OSM_POIS',
                                'OSM_ROADS', 'OSM_HOSPITALS', 'OSM_BOUNDARIES');
  l_osm_columns t_list := t_list(
    'FEATURE_ID|Feature ID|OSM type and ID, e.g. way/123456|',
    'OSM_TYPE|OSM type|node, way or relation|',
    'OSM_ID|OSM ID|ID of the object in OpenStreetMap|',
    'OSM_URL|OSM link|Link to the object on openstreetmap.org|',
    'NAME|Name|Name from the OSM tag name, if present|',
    'TAGS|OSM tags|All tags of the object as JSON text (VARCHAR2 with IS JSON check, readable by Oracle Spatial Studio)|',
    'GEOM|Geometry|Geometry from GeoJSON, SRID 4326, © OpenStreetMap contributors|');

  l_tab_names CONSTANT t_list := t_list('Display', 'Description', 'Source', 'License', 'Feature', 'Demo_Step');
  l_col_names CONSTANT t_list := t_list('Display', 'Description', 'Unit');

  l_ok   PLS_INTEGER := 0;
  l_warn PLS_INTEGER := 0;

  -- n-th field of a line with | as delimiter
  FUNCTION field(p_line IN VARCHAR2, p_pos IN PLS_INTEGER) RETURN VARCHAR2 IS
    l_start PLS_INTEGER := 1;
    l_end   PLS_INTEGER;
  BEGIN
    FOR i IN 1 .. p_pos - 1 LOOP
      l_start := INSTR(p_line, '|', l_start) + 1;
      IF l_start = 1 THEN
        RETURN NULL;                                   -- fewer fields than p_pos
      END IF;
    END LOOP;
    l_end := INSTR(p_line, '|', l_start);
    RETURN CASE WHEN l_end = 0 THEN SUBSTR(p_line, l_start)
                ELSE SUBSTR(p_line, l_start, l_end - l_start) END;
  END field;

  -- Sets annotations for a table (p_column NULL) or a column.
  -- p_values(i) belongs to p_names(i); empty values are only removed.
  PROCEDURE annotate(p_table  IN VARCHAR2,
                     p_column IN VARCHAR2,
                     p_names  IN t_list,
                     p_values IN t_list) IS
    l_target VARCHAR2(400);
    l_drop   VARCHAR2(4000);
    l_add    VARCHAR2(32767);
    FUNCTION ddl(p_clause IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
      IF p_column IS NULL THEN
        RETURN 'ALTER TABLE ' || l_target || ' ANNOTATIONS (' || p_clause || ')';
      END IF;
      RETURN 'ALTER TABLE ' || l_target || ' MODIFY (' || DBMS_ASSERT.ENQUOTE_NAME(p_column)
             || ' ANNOTATIONS (' || p_clause || '))';
    END ddl;
  BEGIN
    l_target := DBMS_ASSERT.SIMPLE_SQL_NAME(p_table);
    FOR i IN 1 .. p_names.COUNT LOOP
      l_drop := l_drop || CASE WHEN l_drop IS NOT NULL THEN ', ' END
                       || 'DROP IF EXISTS ' || p_names(i);
      IF p_values(i) IS NOT NULL THEN
        l_add := l_add || CASE WHEN l_add IS NOT NULL THEN ', ' END
                       || 'ADD ' || p_names(i) || ' ''' || REPLACE(p_values(i), '''', '''''') || '''';
      END IF;
    END LOOP;

    EXECUTE IMMEDIATE ddl(l_drop);
    IF l_add IS NOT NULL THEN
      EXECUTE IMMEDIATE ddl(l_add);
    END IF;
    l_ok := l_ok + 1;
  EXCEPTION
    WHEN OTHERS THEN
      l_warn := l_warn + 1;
      DBMS_OUTPUT.PUT_LINE('WARNING ' || p_table || CASE WHEN p_column IS NOT NULL THEN '.' || p_column END
                           || ' -> ' || SQLERRM);
  END annotate;

BEGIN
  -- Tables
  FOR i IN 1 .. l_tables.COUNT LOOP
    annotate(field(l_tables(i), 1), NULL, l_tab_names,
             t_list(field(l_tables(i), 2), field(l_tables(i), 3), field(l_tables(i), 4),
                    field(l_tables(i), 5), field(l_tables(i), 6), field(l_tables(i), 7)));
  END LOOP;

  -- Columns
  FOR i IN 1 .. l_columns.COUNT LOOP
    annotate(field(l_columns(i), 1), field(l_columns(i), 2), l_col_names,
             t_list(field(l_columns(i), 3), field(l_columns(i), 4), field(l_columns(i), 5)));
  END LOOP;

  -- Columns of the OSM tables
  FOR t IN 1 .. l_osm_tables.COUNT LOOP
    FOR c IN 1 .. l_osm_columns.COUNT LOOP
      annotate(l_osm_tables(t), field(l_osm_columns(c), 1), l_col_names,
               t_list(field(l_osm_columns(c), 2), field(l_osm_columns(c), 3), field(l_osm_columns(c), 4)));
    END LOOP;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('OK      ' || l_ok || ' tables and columns annotated, ' || l_warn || ' warnings');
END;
/

--------------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------------
SET FEEDBACK ON

PROMPT
PROMPT --- Annotations per table (annotated columns / all columns)
SELECT t.table_name,
       MAX(CASE WHEN u.column_name IS NULL AND u.annotation_name = 'DISPLAY'
                THEN u.annotation_value END)                          AS display,
       COUNT(DISTINCT u.column_name)                                  AS annotated_columns,
       (SELECT COUNT(*) FROM user_tab_cols c
        WHERE  c.table_name = t.table_name AND c.hidden_column = 'NO') AS all_columns
FROM   user_tables t
LEFT   JOIN user_annotations_usage u
       ON  u.object_name = t.table_name
       AND u.object_type = 'TABLE'
WHERE  t.table_name NOT LIKE 'RDF\_NETWORK#%' ESCAPE '\'
GROUP  BY t.table_name
ORDER  BY CASE WHEN t.table_name LIKE 'STG\_%' ESCAPE '\' THEN 2 ELSE 1 END, t.table_name;

PROMPT
PROMPT --- Example: all annotations as JSON per column
SELECT object_name, column_name,
       JSON_OBJECTAGG(annotation_name VALUE annotation_value) AS annotations
FROM   user_annotations_usage
WHERE  object_name = 'WATCH_STREAM'
GROUP  BY object_name, column_name;

SPOOL OFF
