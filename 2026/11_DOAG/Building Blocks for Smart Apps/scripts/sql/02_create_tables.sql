--------------------------------------------------------------------------------
-- File       : 02_create_tables.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Creates all tables for the dataset in folder data:
--              target tables (relational, JSON, spatial) and staging tables
--              for the loader.
--              Spatial metadata and indexes: 07_create_spatial_indexes.sql
--              RDF network, graphs, rulebase: 08_create_rdf_network.sql
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as the demo user (see 00_create_user.sql)
--                sql doag2026@<tns_alias> @02_create_tables.sql
-- Re-runnable: yes (CREATE ... IF NOT EXISTS).
--              Changed columns are not applied to existing tables: run
--              98_cleanup.sql first.
-- Conventions: Coordinates WGS 84 (SRID 4326), longitude before latitude.
--              Timestamps as TIMESTAMP WITH TIME ZONE (Europe/Berlin).
--              Truth values as BOOLEAN. Spatial, text and vector indexes
--              are created only after loading (07, 06, 05 or in the demo).
-- Log        : logs/sql/02_create_tables.log in the project folder,
--              overwritten on every run
--------------------------------------------------------------------------------

SET DEFINE OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/02_create_tables.log

PROMPT
PROMPT === 02 Create tables ===

-- Do not run as ADMIN by mistake
BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the demo user, not as ADMIN.');
  END IF;
END;
/

--==============================================================================
-- A. Care network and road network (data/graph, data/spatial/road_*.csv)
--    Basis for the SQL property graph (demo step 5)
--==============================================================================

PROMPT --- road_nodes, road_links
CREATE TABLE IF NOT EXISTS road_nodes (
  node_id   VARCHAR2(10)  NOT NULL,
  name      VARCHAR2(100) NOT NULL,
  lat       NUMBER(9,6)   NOT NULL,
  lon       NUMBER(9,6)   NOT NULL,
  geom      SDO_GEOMETRY,
  CONSTRAINT pk_road_nodes PRIMARY KEY (node_id)
);

CREATE TABLE IF NOT EXISTS road_links (
  link_id        VARCHAR2(10) NOT NULL,
  start_node_id  VARCHAR2(10) NOT NULL,
  end_node_id    VARCHAR2(10) NOT NULL,
  road_class     VARCHAR2(30),
  speed_kmh      NUMBER(3),
  length_m       NUMBER(7),
  cost_s         NUMBER(6),
  direction      VARCHAR2(10),
  CONSTRAINT pk_road_links       PRIMARY KEY (link_id),
  CONSTRAINT fk_road_links_start FOREIGN KEY (start_node_id) REFERENCES road_nodes (node_id),
  CONSTRAINT fk_road_links_end   FOREIGN KEY (end_node_id)   REFERENCES road_nodes (node_id)
);

PROMPT --- providers, devices, patients
CREATE TABLE IF NOT EXISTS providers (
  provider_id           VARCHAR2(10)  NOT NULL,
  name                  VARCHAR2(100) NOT NULL,
  provider_type         VARCHAR2(30)  NOT NULL,
  specialty             VARCHAR2(60),
  city                  VARCHAR2(60),
  lat                   NUMBER(9,6)   NOT NULL,
  lon                   NUMBER(9,6)   NOT NULL,
  nearest_road_node_id  VARCHAR2(10),
  accepts_acute         BOOLEAN       NOT NULL,
  geom                  SDO_GEOMETRY,
  CONSTRAINT pk_providers           PRIMARY KEY (provider_id),
  CONSTRAINT fk_providers_road_node FOREIGN KEY (nearest_road_node_id) REFERENCES road_nodes (node_id)
);

CREATE TABLE IF NOT EXISTS devices (
  device_id         VARCHAR2(10) NOT NULL,
  provider_id       VARCHAR2(10) NOT NULL,
  modality          VARCHAR2(20) NOT NULL,
  field_strength_t  NUMBER(3,1),
  design            VARCHAR2(20),
  CONSTRAINT pk_devices          PRIMARY KEY (device_id),
  CONSTRAINT fk_devices_provider FOREIGN KEY (provider_id) REFERENCES providers (provider_id)
);

CREATE TABLE IF NOT EXISTS patients (
  patient_id      VARCHAR2(10) NOT NULL,
  first_name      VARCHAR2(40) NOT NULL,
  last_initial    VARCHAR2(3),
  birth_year      NUMBER(4),
  sex             VARCHAR2(1),
  home_city       VARCHAR2(60),
  insurance       VARCHAR2(3),
  gp_provider_id  VARCHAR2(10),
  CONSTRAINT pk_patients     PRIMARY KEY (patient_id),
  CONSTRAINT ck_patients_sex CHECK (sex IN ('w', 'm')),
  CONSTRAINT ck_patients_ins CHECK (insurance IN ('GKV', 'PKV')),
  CONSTRAINT fk_patients_gp  FOREIGN KEY (gp_provider_id) REFERENCES providers (provider_id)
);

PROMPT --- appointment_slots, provider_relations, patient_provider_relations
CREATE TABLE IF NOT EXISTS appointment_slots (
  slot_id       VARCHAR2(10) NOT NULL,
  provider_id   VARCHAR2(10) NOT NULL,
  device_id     VARCHAR2(10),
  slot_start    TIMESTAMP WITH TIME ZONE NOT NULL,
  duration_min  NUMBER(4)    NOT NULL,
  slot_type     VARCHAR2(30) NOT NULL,
  status        VARCHAR2(10) NOT NULL,
  CONSTRAINT pk_appointment_slots   PRIMARY KEY (slot_id),
  CONSTRAINT ck_appointment_status  CHECK (status IN ('frei', 'belegt')),
  CONSTRAINT fk_appointment_provider FOREIGN KEY (provider_id) REFERENCES providers (provider_id),
  CONSTRAINT fk_appointment_device   FOREIGN KEY (device_id)   REFERENCES devices (device_id)
);

CREATE TABLE IF NOT EXISTS provider_relations (
  relation_id      VARCHAR2(10) NOT NULL,
  src_provider_id  VARCHAR2(10) NOT NULL,
  dst_provider_id  VARCHAR2(10) NOT NULL,
  relation_type    VARCHAR2(30) NOT NULL,
  CONSTRAINT pk_provider_relations PRIMARY KEY (relation_id),
  CONSTRAINT fk_prov_rel_src FOREIGN KEY (src_provider_id) REFERENCES providers (provider_id),
  CONSTRAINT fk_prov_rel_dst FOREIGN KEY (dst_provider_id) REFERENCES providers (provider_id)
);

CREATE TABLE IF NOT EXISTS patient_provider_relations (
  relation_id    VARCHAR2(10) NOT NULL,
  patient_id     VARCHAR2(10) NOT NULL,
  provider_id    VARCHAR2(10) NOT NULL,
  relation_type  VARCHAR2(30) NOT NULL,
  since          DATE,
  CONSTRAINT pk_patient_provider_relations PRIMARY KEY (relation_id),
  CONSTRAINT fk_pat_rel_patient  FOREIGN KEY (patient_id)  REFERENCES patients (patient_id),
  CONSTRAINT fk_pat_rel_provider FOREIGN KEY (provider_id) REFERENCES providers (provider_id)
);

-- Index the foreign keys (property graph, joins, no locking issues)
CREATE INDEX IF NOT EXISTS ix_road_links_start      ON road_links (start_node_id);
CREATE INDEX IF NOT EXISTS ix_road_links_end        ON road_links (end_node_id);
CREATE INDEX IF NOT EXISTS ix_providers_road_node   ON providers (nearest_road_node_id);
CREATE INDEX IF NOT EXISTS ix_devices_provider      ON devices (provider_id);
CREATE INDEX IF NOT EXISTS ix_patients_gp           ON patients (gp_provider_id);
CREATE INDEX IF NOT EXISTS ix_appointment_provider  ON appointment_slots (provider_id);
CREATE INDEX IF NOT EXISTS ix_appointment_device    ON appointment_slots (device_id);
CREATE INDEX IF NOT EXISTS ix_prov_rel_src          ON provider_relations (src_provider_id);
CREATE INDEX IF NOT EXISTS ix_prov_rel_dst          ON provider_relations (dst_provider_id);
CREATE INDEX IF NOT EXISTS ix_pat_rel_patient       ON patient_provider_relations (patient_id);
CREATE INDEX IF NOT EXISTS ix_pat_rel_provider      ON patient_provider_relations (provider_id);

--==============================================================================
-- B. Case library (data/casebase) - full-text and vector search (step 3)
--==============================================================================

PROMPT --- case_notes
CREATE TABLE IF NOT EXISTS case_notes (
  case_id          VARCHAR2(10)   NOT NULL,
  recorded_on      DATE           NOT NULL,
  age              NUMBER(3),
  sex              VARCHAR2(1),
  body_region      VARCHAR2(30),
  side             VARCHAR2(10),
  note_text        VARCHAR2(4000) NOT NULL,
  diagnosis_code   VARCHAR2(40)   NOT NULL,
  diagnosis_label  VARCHAR2(100),
  confirmed_by     VARCHAR2(20),
  CONSTRAINT pk_case_notes     PRIMARY KEY (case_id),
  CONSTRAINT ck_case_notes_sex CHECK (sex IN ('w', 'm'))
);

--==============================================================================
-- C. Movement data (data/stream) - spatial streaming (steps 2 and 6)
--    These tables hold the complete recording. Later, the demo replays it
--    as a time-lapse into a separate table with DBMS_SCHEDULER.
--==============================================================================

PROMPT --- watch_stream, car_stream
CREATE TABLE IF NOT EXISTS watch_stream (
  device_id    VARCHAR2(20) NOT NULL,
  seq_no       NUMBER(8)    NOT NULL,
  patient_id   VARCHAR2(10),
  event_ts     TIMESTAMP WITH TIME ZONE NOT NULL,   -- measurement time (event time)
  ingest_ts    TIMESTAMP WITH TIME ZONE NOT NULL,   -- arrival time
  buffered     BOOLEAN      NOT NULL,               -- buffered in the dead zone
  lat          NUMBER(9,6)  NOT NULL,
  lon          NUMBER(9,6)  NOT NULL,
  ele_m        NUMBER(6,1),
  hr_bpm       NUMBER(3),
  cadence_spm  NUMBER(3),
  acc_peak_g   NUMBER(5,2),
  battery_pct  NUMBER(3),
  phase        VARCHAR2(20),                        -- ground truth, not for detection
  geom         SDO_GEOMETRY,
  CONSTRAINT pk_watch_stream         PRIMARY KEY (device_id, seq_no),
  CONSTRAINT fk_watch_stream_patient FOREIGN KEY (patient_id) REFERENCES patients (patient_id)
);
CREATE INDEX IF NOT EXISTS ix_watch_stream_patient ON watch_stream (patient_id);

CREATE TABLE IF NOT EXISTS car_stream (
  device_id    VARCHAR2(20) NOT NULL,
  seq_no       NUMBER(8)    NOT NULL,
  event_ts     TIMESTAMP WITH TIME ZONE NOT NULL,
  ingest_ts    TIMESTAMP WITH TIME ZONE NOT NULL,
  lat          NUMBER(9,6)  NOT NULL,
  lon          NUMBER(9,6)  NOT NULL,
  speed_kmh    NUMBER(5,1),
  heading_deg  NUMBER(3),
  geom         SDO_GEOMETRY,
  CONSTRAINT pk_car_stream PRIMARY KEY (device_id, seq_no)
);

--==============================================================================
-- D. Places of the story (data/spatial, synthetic on OSM geometry, ODbL 1.0)
--==============================================================================

PROMPT --- trail_segments, parking_lots, pois, zones
CREATE TABLE IF NOT EXISTS trail_segments (
  segment_id    VARCHAR2(10) NOT NULL,
  trail_id      VARCHAR2(10) NOT NULL,
  trail_name    VARCHAR2(60),
  segment_name  VARCHAR2(60),
  length_m      NUMBER(6),
  elev_from_m   NUMBER(5),
  elev_to_m     NUMBER(5),
  grade_pct     NUMBER(5,1),                        -- grade in percent, negative = downhill
  difficulty    VARCHAR2(20),
  geom          SDO_GEOMETRY NOT NULL,
  CONSTRAINT pk_trail_segments PRIMARY KEY (segment_id)
);

CREATE TABLE IF NOT EXISTS parking_lots (
  parking_id  VARCHAR2(10)  NOT NULL,
  name        VARCHAR2(100) NOT NULL,
  capacity    NUMBER(5),
  car_access  BOOLEAN       NOT NULL,              -- reachable by car
  geom        SDO_GEOMETRY  NOT NULL,
  CONSTRAINT pk_parking_lots PRIMARY KEY (parking_id)
);

CREATE TABLE IF NOT EXISTS pois (
  poi_id    VARCHAR2(10)  NOT NULL,
  name      VARCHAR2(100) NOT NULL,
  poi_type  VARCHAR2(30),
  geom      SDO_GEOMETRY  NOT NULL,
  CONSTRAINT pk_pois PRIMARY KEY (poi_id)
);

CREATE TABLE IF NOT EXISTS zones (
  zone_id    VARCHAR2(10)  NOT NULL,
  zone_type  VARCHAR2(20)  NOT NULL,                -- dead zone, geofence
  name       VARCHAR2(100) NOT NULL,
  note       VARCHAR2(400),
  geom       SDO_GEOMETRY  NOT NULL,
  CONSTRAINT pk_zones PRIMARY KEY (zone_id)
);

--==============================================================================
-- E. OpenStreetMap extracts (data/spatial/osm_*.geojson, ODbL 1.0)
--    All six tables share the same structure. Mixed geometries (parking,
--    pois) are allowed.
--    The OSM tags are stored as JSON text in VARCHAR2(4000) with an IS JSON
--    check (largest tag object: 1,423 bytes) instead of the data type JSON,
--    so that Oracle Spatial Studio can display the tables. JSON_VALUE,
--    JSON_TABLE and the dot notation (t.tags.highway) work thanks to the
--    IS JSON constraint.
--==============================================================================

PROMPT --- osm_layers and osm_*
CREATE TABLE IF NOT EXISTS osm_layers (
  layer_name          VARCHAR2(30)   NOT NULL,
  attribution         VARCHAR2(200)  NOT NULL,
  license             VARCHAR2(30)   NOT NULL,
  license_url         VARCHAR2(200),
  copyright_url       VARCHAR2(200),
  source              VARCHAR2(200),
  osm_base_timestamp  TIMESTAMP WITH TIME ZONE,
  downloaded_at       TIMESTAMP WITH TIME ZONE,
  overpass_query      VARCHAR2(4000),
  CONSTRAINT pk_osm_layers PRIMARY KEY (layer_name)
);

DECLARE
  TYPE t_names IS TABLE OF VARCHAR2(30);
  l_tabs t_names := t_names('OSM_TRAILS', 'OSM_PARKING', 'OSM_POIS',
                            'OSM_ROADS', 'OSM_HOSPITALS', 'OSM_BOUNDARIES');
BEGIN
  FOR i IN 1 .. l_tabs.COUNT LOOP
    EXECUTE IMMEDIATE
      'CREATE TABLE IF NOT EXISTS ' || l_tabs(i) || ' (
         feature_id  VARCHAR2(40)  NOT NULL,
         osm_type    VARCHAR2(10)  NOT NULL,
         osm_id      NUMBER(19)    NOT NULL,
         osm_url     VARCHAR2(200),
         name        VARCHAR2(400),
         tags        VARCHAR2(4000),
         geom        SDO_GEOMETRY  NOT NULL,
         CONSTRAINT pk_' || LOWER(l_tabs(i)) || ' PRIMARY KEY (feature_id),
         CONSTRAINT ck_' || LOWER(l_tabs(i)) || '_tags CHECK (tags IS JSON),
         CONSTRAINT ck_' || LOWER(l_tabs(i)) || '_type CHECK (osm_type IN (''node'', ''way'', ''relation''))
       )';
    DBMS_OUTPUT.PUT_LINE('OK      ' || l_tabs(i));
  END LOOP;
END;
/

--==============================================================================
-- F. Symptom reports, diagnoses, medication recommendations (data/json)
--    Demo steps 1 and 3: compare Jonas' symptoms with the reports of others,
--    read the diagnoses made and the medications recommended. The JSON
--    documents are split into relational rows during the load.
--    Only age and gender of the persons are taken over; name, address,
--    date of birth, previous illnesses and measurements stay in the file.
--
--    Source per table
--      symptom_reports             FHIR Condition (problem-list-item) from
--                                  fhir_bundles_all_patients.ndjson and the
--                                  app report symptom_report_jonas.json
--      diagnoses                   FHIR Condition (encounter-diagnosis),
--                                  evidence refers to the symptom report
--      medication_recommendations  FHIR MedicationRequest, reason refers to
--                                  diagnosis and symptom report
--==============================================================================

PROMPT --- symptom_reports, diagnoses, medication_recommendations
CREATE TABLE IF NOT EXISTS symptom_reports (
  report_id             VARCHAR2(30)   NOT NULL,    -- Condition.id or report_id of the app
  source                VARCHAR2(10)   NOT NULL,    -- fhir or app
  reported_by           VARCHAR2(60),               -- health app or GP practice
  reported_on           DATE           NOT NULL,
  age                   NUMBER(3)      NOT NULL,    -- age on 16.11.2026 (from the date of birth)
  gender                VARCHAR2(10)   NOT NULL,    -- female or male
  report_text           VARCHAR2(4000) NOT NULL,    -- free-text description of the symptoms (German)
  body_site_code        VARCHAR2(60),               -- region and side, e.g. untere_extremitaet_rechts
  body_site_text        VARCHAR2(100),
  severity              VARCHAR2(20),               -- leicht, mittel, schwer (mild, moderate, severe)
  clinical_status       VARCHAR2(20),               -- active, recurrence, resolved
  -- Structured answers, only for reports from the app
  mechanism             VARCHAR2(30),
  audible_pop           BOOLEAN,
  swelling_onset_hours  NUMBER(4,1),
  instability           BOOLEAN,
  locking               BOOLEAN,
  weight_bearing        VARCHAR2(30),
  pain_nrs              NUMBER(2),
  geom                  SDO_GEOMETRY,               -- location of the report, app only
  -- Embedding of report_text, filled by 05_create_embeddings.sql
  -- (all-MiniLM-L12-v2, 384 dimensions). The dimension is left open, so
  -- that the embedding model can be exchanged.
  report_embedding      VECTOR(*, FLOAT32),
  CONSTRAINT pk_symptom_reports        PRIMARY KEY (report_id),
  CONSTRAINT ck_symptom_reports_source CHECK (source IN ('fhir', 'app')),
  CONSTRAINT ck_symptom_reports_gender CHECK (gender IN ('female', 'male', 'other', 'unknown')),
  CONSTRAINT ck_symptom_reports_pain   CHECK (pain_nrs BETWEEN 0 AND 10)
);

CREATE TABLE IF NOT EXISTS diagnoses (
  diagnosis_id          VARCHAR2(30)  NOT NULL,     -- Condition.id
  report_id             VARCHAR2(30)  NOT NULL,     -- Condition.evidence -> symptom report
  diagnosis_code        VARCHAR2(60)  NOT NULL,     -- own CodeSystem; knee codes as in case_notes
  diagnosis_label       VARCHAR2(100) NOT NULL,
  body_site_code        VARCHAR2(60),
  body_site_text        VARCHAR2(100),
  verification_status   VARCHAR2(20)  NOT NULL,     -- confirmed or provisional
  confirmed_by          VARCHAR2(20),               -- clinical exam, MRI, X-ray, lab, ECG
  clinical_status       VARCHAR2(20),
  diagnosed_on          DATE          NOT NULL,     -- Condition.recordedDate
  diagnosed_by          VARCHAR2(10),               -- Condition.asserter -> PROVIDERS
  CONSTRAINT pk_diagnoses          PRIMARY KEY (diagnosis_id),
  CONSTRAINT fk_diagnoses_report   FOREIGN KEY (report_id)    REFERENCES symptom_reports (report_id),
  CONSTRAINT fk_diagnoses_provider FOREIGN KEY (diagnosed_by) REFERENCES providers (provider_id)
);
CREATE INDEX IF NOT EXISTS ix_diagnoses_report   ON diagnoses (report_id);
CREATE INDEX IF NOT EXISTS ix_diagnoses_provider ON diagnoses (diagnosed_by);
CREATE INDEX IF NOT EXISTS ix_diagnoses_code     ON diagnoses (diagnosis_code);

CREATE TABLE IF NOT EXISTS medication_recommendations (
  recommendation_id     VARCHAR2(30)  NOT NULL,     -- MedicationRequest.id
  diagnosis_id          VARCHAR2(30)  NOT NULL,     -- MedicationRequest.reason[0] -> diagnosis
  report_id             VARCHAR2(30)  NOT NULL,     -- MedicationRequest.reason[1] -> symptom report
  medication_code       VARCHAR2(40)  NOT NULL,
  medication_text       VARCHAR2(200) NOT NULL,
  dosage_text           VARCHAR2(200),
  intent                VARCHAR2(20)  NOT NULL,     -- proposal = recommendation, order = prescription
  status                VARCHAR2(20),               -- active or completed
  recommended_on        DATE          NOT NULL,     -- MedicationRequest.authoredOn
  recommended_by        VARCHAR2(10),               -- MedicationRequest.requester -> PROVIDERS
  CONSTRAINT pk_medication_recommendations PRIMARY KEY (recommendation_id),
  CONSTRAINT ck_medication_rec_intent      CHECK (intent IN ('proposal', 'order')),
  CONSTRAINT fk_medication_rec_diagnosis   FOREIGN KEY (diagnosis_id)   REFERENCES diagnoses (diagnosis_id),
  CONSTRAINT fk_medication_rec_report      FOREIGN KEY (report_id)      REFERENCES symptom_reports (report_id),
  CONSTRAINT fk_medication_rec_provider    FOREIGN KEY (recommended_by) REFERENCES providers (provider_id)
);
CREATE INDEX IF NOT EXISTS ix_medication_rec_diagnosis ON medication_recommendations (diagnosis_id);
CREATE INDEX IF NOT EXISTS ix_medication_rec_report    ON medication_recommendations (report_id);
CREATE INDEX IF NOT EXISTS ix_medication_rec_provider  ON medication_recommendations (recommended_by);

-- View for the question "Which diagnoses and medications were there for similar
-- symptoms?": one row per symptom report, diagnosis and recommendation
CREATE OR REPLACE VIEW symptom_diagnosis_medication_v AS
SELECT s.report_id,
       s.age,
       s.gender,
       s.report_text,
       s.body_site_text,
       s.severity,
       d.diagnosis_id,
       d.diagnosis_code,
       d.diagnosis_label,
       d.verification_status,
       d.confirmed_by,
       m.medication_code,
       m.medication_text,
       m.dosage_text,
       m.intent
FROM   symptom_reports s
LEFT   JOIN diagnoses d                  ON d.report_id    = s.report_id
LEFT   JOIN medication_recommendations m ON m.diagnosis_id = d.diagnosis_id
WHERE  s.source = 'fhir';

--==============================================================================
-- G. RDF (data/rdf) - demo step 4: no tables in this script
--    08_create_rdf_network.sql creates the RDF network RDF_NETWORK, the
--    graphs KNEE_KG and FMA, the staging table STG_RDF_TRIPLES and the
--    rulebase.
--    Native data type: in the RDF network RDF_NETWORK (the only one on
--    Autonomous AI Database; it is schema-private) table_name and
--    column_name in SEM_APIS.CREATE_RDF_GRAPH must be NULL. A separate
--    table with a column of type SDO_RDF_TRIPLE_S cannot be attached there
--    as an application table. Instead, the view RDF_NETWORK#RDFT_<GRAPH>,
--    created by CREATE_RDF_GRAPH, uses the type SDO_RDF_TRIPLE_S;
--    09a_load_knee_kg.sql loads KNEE_KG through it.
--==============================================================================

--==============================================================================
-- H. Staging tables for the loader (03_load_data.sql)
--    SQLcl LOAD writes only into these. All columns are text and are named
--    like the columns of the CSV files. Conversion happens afterwards in SQL.
--==============================================================================

PROMPT --- Staging tables
CREATE TABLE IF NOT EXISTS stg_road_nodes (
  node_id VARCHAR2(4000), name VARCHAR2(4000), lat VARCHAR2(4000), lon VARCHAR2(4000),
  geometry_wkt VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_road_links (
  link_id VARCHAR2(4000), start_node_id VARCHAR2(4000), end_node_id VARCHAR2(4000),
  road_class VARCHAR2(4000), speed_kmh VARCHAR2(4000), length_m VARCHAR2(4000),
  cost_s VARCHAR2(4000), direction VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_providers (
  provider_id VARCHAR2(4000), name VARCHAR2(4000), provider_type VARCHAR2(4000),
  specialty VARCHAR2(4000), city VARCHAR2(4000), lat VARCHAR2(4000), lon VARCHAR2(4000),
  nearest_road_node_id VARCHAR2(4000), accepts_acute VARCHAR2(4000), geometry_wkt VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_devices (
  device_id VARCHAR2(4000), provider_id VARCHAR2(4000), modality VARCHAR2(4000),
  field_strength_t VARCHAR2(4000), design VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_patients (
  patient_id VARCHAR2(4000), first_name VARCHAR2(4000), last_initial VARCHAR2(4000),
  birth_year VARCHAR2(4000), sex VARCHAR2(4000), home_city VARCHAR2(4000),
  insurance VARCHAR2(4000), gp_provider_id VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_appointment_slots (
  slot_id VARCHAR2(4000), provider_id VARCHAR2(4000), device_id VARCHAR2(4000),
  slot_start VARCHAR2(4000), duration_min VARCHAR2(4000), slot_type VARCHAR2(4000),
  status VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_provider_relations (
  relation_id VARCHAR2(4000), src_provider_id VARCHAR2(4000), dst_provider_id VARCHAR2(4000),
  relation_type VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_patient_provider_relations (
  relation_id VARCHAR2(4000), patient_id VARCHAR2(4000), provider_id VARCHAR2(4000),
  relation_type VARCHAR2(4000), since VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_case_notes (
  case_id VARCHAR2(4000), recorded_on VARCHAR2(4000), age VARCHAR2(4000), sex VARCHAR2(4000),
  body_region VARCHAR2(4000), side VARCHAR2(4000), note_text VARCHAR2(4000),
  diagnosis_code VARCHAR2(4000), diagnosis_label VARCHAR2(4000), confirmed_by VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_watch_stream (
  seq_no VARCHAR2(4000), device_id VARCHAR2(4000), patient_id VARCHAR2(4000),
  event_ts VARCHAR2(4000), ingest_ts VARCHAR2(4000), buffered VARCHAR2(4000),
  lat VARCHAR2(4000), lon VARCHAR2(4000), ele_m VARCHAR2(4000), hr_bpm VARCHAR2(4000),
  cadence_spm VARCHAR2(4000), acc_peak_g VARCHAR2(4000), battery_pct VARCHAR2(4000),
  phase VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_car_stream (
  seq_no VARCHAR2(4000), device_id VARCHAR2(4000), event_ts VARCHAR2(4000),
  ingest_ts VARCHAR2(4000), lat VARCHAR2(4000), lon VARCHAR2(4000),
  speed_kmh VARCHAR2(4000), heading_deg VARCHAR2(4000));

-- Line-based files (N-Triples in 09a and 09b): one line = one record
CREATE TABLE IF NOT EXISTS stg_text_lines (
  line_text VARCHAR2(32767));

-- JSON, GeoJSON and NDJSON files. SQLcl LOAD does not read JSON; the
-- documents therefore come in chunks from data/_load/json_chunks.csv (at most
-- 1000 characters per chunk) and are reassembled into documents in 03 with
-- PL/SQL.
--   DOC_NO 0     = document without "features" (header of the FeatureCollection
--                  or the complete symptom report)
--   DOC_NO 1..n  = features in file order; for NDJSON (FHIR bundles) one
--                  document per line
CREATE TABLE IF NOT EXISTS stg_json_chunks (
  layer VARCHAR2(4000), doc_no VARCHAR2(4000), chunk_no VARCHAR2(4000),
  chunk_text VARCHAR2(4000));

CREATE TABLE IF NOT EXISTS stg_json_docs (
  layer          VARCHAR2(30) NOT NULL,
  doc_no         NUMBER(6)    NOT NULL,
  json_document  JSON         NOT NULL,
  CONSTRAINT stg_json_docs_pk PRIMARY KEY (layer, doc_no));

--==============================================================================
-- I. Comments
--==============================================================================

COMMENT ON TABLE road_nodes                 IS 'Simplified road network, nodes (fallback for routing only)';
COMMENT ON TABLE road_links                 IS 'Simplified road network, links with travel time cost_s in seconds';
COMMENT ON TABLE providers                  IS 'GP practices, radiology centres, hospitals, physiotherapy (fictitious, placed on real main roads)';
COMMENT ON TABLE devices                    IS 'MRI and X-ray devices per care provider';
COMMENT ON TABLE patients                   IS 'Persons in the care network (P0001 = Jonas)';
COMMENT ON TABLE appointment_slots          IS 'Appointments per care provider and device, status frei (free) or belegt (booked)';
COMMENT ON TABLE provider_relations         IS 'Referrals and cooperations between care providers';
COMMENT ON TABLE patient_provider_relations IS 'GP and treatment relationships';
COMMENT ON TABLE case_notes                 IS 'Case library: 290 German case notes with confirmed diagnosis';
COMMENT ON TABLE watch_stream               IS 'Fitness watch of Jonas, one measurement every 5 s, complete recording';
COMMENT ON TABLE car_stream                 IS 'Car of the friend, one measurement every 10 s';
COMMENT ON TABLE trail_segments             IS 'Felsenpfad loop trail and neighbouring trails on real OSM paths (fictitious names), grade per segment';
COMMENT ON TABLE parking_lots               IS 'Parking lots of the story at real OSM parking lots (fictitious names), car_access = reachable by car';
COMMENT ON TABLE pois                       IS 'Places of the story at a real OSM shelter, viewpoint and path junction (fictitious names)';
COMMENT ON TABLE zones                      IS 'Dead zone and geofences of the parking lots';
COMMENT ON TABLE osm_layers                 IS 'Origin and attribution of the OSM extracts: (c) OpenStreetMap contributors, ODbL 1.0';
COMMENT ON TABLE osm_trails                 IS 'OSM: paths and hiking routes around Pottenstein (ODbL 1.0)';
COMMENT ON TABLE osm_parking                IS 'OSM: parking lots around Pottenstein (ODbL 1.0)';
COMMENT ON TABLE osm_pois                   IS 'OSM: shelter huts, viewpoints, signposts around Pottenstein (ODbL 1.0)';
COMMENT ON TABLE osm_roads                  IS 'OSM: motorways down to state roads between Nuremberg and Bayreuth (ODbL 1.0)';
COMMENT ON TABLE osm_hospitals              IS 'OSM: hospitals as points (ODbL 1.0)';
COMMENT ON TABLE osm_boundaries             IS 'OSM: city boundaries of Nuremberg and Fuerth (ODbL 1.0)';
COMMENT ON TABLE symptom_reports            IS 'Symptom reports: 1,458 from the FHIR bundles and Jonas'' app report; only age and gender of the person';
COMMENT ON TABLE diagnoses                  IS 'Diagnoses for the symptom reports (FHIR Condition, encounter-diagnosis)';
COMMENT ON TABLE medication_recommendations IS 'Recommended or prescribed medications per diagnosis (FHIR MedicationRequest)';
COMMENT ON TABLE symptom_diagnosis_medication_v IS 'Symptom report, diagnosis and medication recommendation in one row';

--==============================================================================
-- J. Checks
--==============================================================================

PROMPT
PROMPT --- Created tables
SELECT table_name
FROM   user_tables
WHERE  table_name NOT LIKE 'RDF\_NETWORK#%' ESCAPE '\'
ORDER  BY CASE WHEN table_name LIKE 'STG\_%' ESCAPE '\' THEN 2 ELSE 1 END, table_name;

PROMPT
PROMPT Done. Continue with 03_load_data.sql.

SPOOL OFF
