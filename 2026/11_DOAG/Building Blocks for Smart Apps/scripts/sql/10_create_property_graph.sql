--------------------------------------------------------------------------------
-- File       : 10_create_property_graph.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Creates the SQL property graph CARE_NETWORK for demo step 5
--              ("Who can help, and where?") on top of the relational tables
--              of the care network. No data is copied, the graph only stores
--              metadata; queries with GRAPH_TABLE read the current table data.
--                Vertices  patient   PATIENTS
--                          provider  PROVIDERS (without GEOM: SDO_GEOMETRY is
--                                    not allowed as a property; the
--                                    notebooks join PROVIDERS for spatial
--                                    filters)
--                          device    DEVICES (MRI and X-ray devices)
--                          slot      APPOINTMENT_SLOTS
--                Edges     care_relation      patient  -> provider
--                                             (hat_hausarzt, war_in_behandlung)
--                          provider_relation  provider -> provider
--                                             (ueberweist_an, kooperiert_mit)
--                          operates           provider -> device  (DEVICES)
--                          offers             provider -> slot
--                                             (APPOINTMENT_SLOTS)
--              DEVICES and APPOINTMENT_SLOTS are vertex tables and edge tables
--              at the same time, with different aliases.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as the demo user, after 03_load_data.sql
--                sql doag2026@<tns_alias> @10_create_property_graph.sql
-- Privileges : CREATE PROPERTY GRAPH (DB_DEVELOPER_ROLE, see 00_create_user.sql)
-- Re-runnable: yes (CREATE OR REPLACE PROPERTY GRAPH)
-- Mode       : TRUSTED (default). The edge tables OFFERS and OPERATES reuse
--              vertex tables, and their destination key is the primary key
--              of the same row, not a foreign key. ENFORCED MODE expects a
--              foreign key for every edge key, so it is not used here. Keys
--              are unique anyway: they are the primary keys of the tables.
-- Note       : After a change of a table the graph is based on, compile the
--              graph again: ALTER PROPERTY GRAPH care_network COMPILE;
-- Log        : logs/sql/10_create_property_graph.log in the project folder,
--              overwritten on every run
--------------------------------------------------------------------------------

SET DEFINE OFF
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/10_create_property_graph.log

PROMPT
PROMPT === 10 Create the property graph CARE_NETWORK ===

BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the demo user, not as ADMIN.');
  END IF;
END;
/

--==============================================================================
-- 1. Check the base tables
--    The graph is only useful when the care network is loaded (03).
--==============================================================================

DECLARE
  l_cnt PLS_INTEGER;
BEGIN
  FOR t IN (SELECT column_value AS table_name
            FROM   TABLE(SYS.ODCIVARCHAR2LIST('PATIENTS', 'PROVIDERS', 'DEVICES', 'APPOINTMENT_SLOTS',
                                              'PATIENT_PROVIDER_RELATIONS', 'PROVIDER_RELATIONS'))) LOOP
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || t.table_name INTO l_cnt;
    IF l_cnt = 0 THEN
      RAISE_APPLICATION_ERROR(-20040, 'Table ' || t.table_name || ' is empty. Run 03_load_data.sql first.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD(t.table_name, 32) || LPAD(l_cnt, 8));
  END LOOP;
END;
/

--==============================================================================
-- 2. Create the property graph
--==============================================================================

PROMPT
PROMPT --- 2. CARE_NETWORK
CREATE OR REPLACE PROPERTY GRAPH care_network
  VERTEX TABLES (
    patients
      KEY (patient_id)
      LABEL patient
      PROPERTIES ARE ALL COLUMNS,
    providers
      KEY (provider_id)
      LABEL provider
      PROPERTIES ARE ALL COLUMNS EXCEPT (geom),
    devices
      KEY (device_id)
      LABEL device
      PROPERTIES ARE ALL COLUMNS,
    appointment_slots
      KEY (slot_id)
      LABEL slot
      PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    patient_provider_relations
      KEY (relation_id)
      SOURCE      KEY (patient_id)      REFERENCES patients (patient_id)
      DESTINATION KEY (provider_id)     REFERENCES providers (provider_id)
      LABEL care_relation
      PROPERTIES (relation_id, relation_type, since),
    provider_relations
      KEY (relation_id)
      SOURCE      KEY (src_provider_id) REFERENCES providers (provider_id)
      DESTINATION KEY (dst_provider_id) REFERENCES providers (provider_id)
      LABEL provider_relation
      PROPERTIES (relation_id, relation_type),
    devices AS operates
      KEY (device_id)
      SOURCE      KEY (provider_id)     REFERENCES providers (provider_id)
      DESTINATION KEY (device_id)       REFERENCES devices (device_id)
      LABEL operates
      NO PROPERTIES,
    appointment_slots AS offers
      KEY (slot_id)
      SOURCE      KEY (provider_id)     REFERENCES providers (provider_id)
      DESTINATION KEY (slot_id)         REFERENCES appointment_slots (slot_id)
      LABEL offers
      NO PROPERTIES
  );

--==============================================================================
-- 3. Checks
--==============================================================================

PROMPT
PROMPT --- 3. Graph elements
COLUMN graph_name FORMAT A16
COLUMN graph_mode FORMAT A10
SELECT graph_name, graph_mode
FROM   user_property_graphs
WHERE  graph_name = 'CARE_NETWORK';

PROMPT
PROMPT --- Vertices and edges per label
COLUMN label FORMAT A20
SELECT 'patient' AS label, COUNT(*) AS elements
FROM   GRAPH_TABLE (care_network MATCH (v IS patient) COLUMNS (v.patient_id AS id))
UNION ALL
SELECT 'provider', COUNT(*)
FROM   GRAPH_TABLE (care_network MATCH (v IS provider) COLUMNS (v.provider_id AS id))
UNION ALL
SELECT 'device', COUNT(*)
FROM   GRAPH_TABLE (care_network MATCH (v IS device) COLUMNS (v.device_id AS id))
UNION ALL
SELECT 'slot', COUNT(*)
FROM   GRAPH_TABLE (care_network MATCH (v IS slot) COLUMNS (v.slot_id AS id))
UNION ALL
SELECT 'care_relation', COUNT(*)
FROM   GRAPH_TABLE (care_network MATCH () -[e IS care_relation]-> () COLUMNS (e.relation_id AS id))
UNION ALL
SELECT 'provider_relation', COUNT(*)
FROM   GRAPH_TABLE (care_network MATCH () -[e IS provider_relation]-> () COLUMNS (e.relation_id AS id))
UNION ALL
SELECT 'operates', COUNT(*)
FROM   GRAPH_TABLE (care_network MATCH (a IS provider) -[e IS operates]-> (b IS device) COLUMNS (b.device_id AS id))
UNION ALL
SELECT 'offers', COUNT(*)
FROM   GRAPH_TABLE (care_network MATCH (a IS provider) -[e IS offers]-> (b IS slot) COLUMNS (b.slot_id AS id));

PROMPT
PROMPT --- Test: Jonas' referral paths from his GP to a radiology with an MRI
COLUMN gp         FORMAT A30
COLUMN specialist FORMAT A40
COLUMN radiology  FORMAT A30
SELECT gp, specialist, radiology, mri_device
FROM   GRAPH_TABLE (care_network
         MATCH (p IS patient WHERE p.patient_id = 'P0001')
               -[r1 IS care_relation WHERE r1.relation_type = 'hat_hausarzt']->      (gp IS provider)
               -[r2 IS provider_relation WHERE r2.relation_type = 'ueberweist_an']-> (spec IS provider)
               -[r3 IS provider_relation WHERE r3.relation_type = 'kooperiert_mit']-> (rad IS provider)
               -[o IS operates]-> (d IS device WHERE d.modality = 'MRT')
         COLUMNS (gp.name   AS gp,
                  spec.name AS specialist,
                  rad.name  AS radiology,
                  d.device_id AS mri_device))
ORDER  BY specialist;

PROMPT
PROMPT Done.

SPOOL OFF
