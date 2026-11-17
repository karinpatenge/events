-- =============================================================================
-- demo_act2_graph_queries.sql   (Act 2: from symptoms to root cause, SQL/PGQ)
--
-- Author:      Karin Patenge
-- Last update: 2026-11-13
--
-- Run in SQLcl, SQL Developer for VS Code or Database Actions as user
-- GRAPHAI, one statement at a time. Read-only.
-- Starting state: incident (@sql/demo_state.sql incident).
-- =============================================================================

-- 0) The situation: how many buildings are cold, where?
SELECT district, COUNT(*) AS cold_buildings, SUM(apartments) AS apartments
FROM   dh_assets
WHERE  asset_type = 'BUILDING' AND health_status = 'ALARM'
GROUP  BY district
ORDER  BY cold_buildings DESC;

-- 0b) A property graph is only a definition over the tables: no copy, no second database
SET LONG 100000
SELECT DBMS_METADATA.GET_DDL('PROPERTY_GRAPH', 'DH_NETWORK') AS ddl FROM dual;
-- Note: The new 26ai function DBMS_DEVELOPER.GET_METADATA does not support property graphs, only relational objects. 

-- 1) Relational way: "what does pump station PS-04 supply?" needs recursion
WITH downstream (asset_id, lvl) AS (
  SELECT to_asset, 1 FROM dh_pipes WHERE from_asset = 'PS-04' AND valve_state = 'OPEN'
  UNION ALL
  SELECT p.to_asset, d.lvl + 1
  FROM   dh_pipes p JOIN downstream d ON p.from_asset = d.asset_id
  WHERE  p.valve_state = 'OPEN'
)
SELECT a.asset_id, a.name, a.building_type, a.apartments, d.lvl AS hops
FROM   downstream d JOIN dh_assets a ON a.asset_id = d.asset_id
WHERE  a.asset_type = 'BUILDING'
ORDER  BY a.asset_id;

-- 2) Same question as a graph pattern: 1 to 4 hops along open pipes
SELECT *
FROM   GRAPH_TABLE (dh_network
         MATCH (ps IS asset WHERE ps.asset_id = 'PS-04')
               -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
               (b IS asset WHERE b.asset_type = 'BUILDING')
         COLUMNS (b.asset_id, b.name, b.building_type, b.apartments,
                  COUNT(p.pipe_id) AS hops))
ORDER  BY asset_id;

-- 3) Anomalies in context: which open anomalies sit upstream of cold buildings?
--    STATUS of an anomaly (DH_ANOMALIES, check constraint DH_ANOM_STATUS_CK):
--      OPEN    current: seen by the last detection run (every 30 s, DH_ANALYTICS)
--      ACK     acknowledged by an operator, still current (allowed, not used in the demo)
--      CLOSED  over, kept as history: not seen for 1 minute, replaced by a limit
--              finding (z-score -> threshold), or a duplicate of an open finding
--    status <> 'CLOSED' = every current finding, acknowledged or not.
SELECT suspect, suspect_name,
       COUNT(DISTINCT cold_building)                                   AS cold_buildings_explained,
       LISTAGG(DISTINCT anomaly_type || ' ' || severity, ', ')         AS evidence
FROM   GRAPH_TABLE (dh_network
         MATCH (an IS anomaly WHERE an.status <> 'CLOSED')
               -[IS detected_on]-> (s IS asset)
               -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
               (b IS asset WHERE b.asset_type = 'BUILDING' AND b.health_status = 'ALARM')
         COLUMNS (s.asset_id AS suspect, s.name AS suspect_name, b.asset_id AS cold_building,
                  an.anomaly_type, an.severity))
GROUP  BY suspect, suspect_name
ORDER  BY cold_buildings_explained DESC;

-- 4) The evidence on the top suspect, incl. the predictive trend of the last days
SELECT anomaly_type, severity, details, hours_to_alarm,
       CAST(FROM_TZ(detected_at, 'UTC') AT LOCAL AS TIMESTAMP) AS since
FROM   dh_anomalies
WHERE  asset_id = 'PS-04' AND status <> 'CLOSED'
ORDER  BY detected_at;

-- 5) Impact: life-critical buildings that depend on PS-04
SELECT *
FROM   GRAPH_TABLE (dh_network
         MATCH (ps IS asset WHERE ps.asset_id = 'PS-04')
               -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
               (b IS asset WHERE b.asset_type = 'BUILDING' AND b.criticality >= 4)
         COLUMNS (b.asset_id, b.name, b.building_type, b.district, b.health_status))
ORDER  BY asset_id;

-- 6) The odd one out: cold buildings NOT explained by an upstream equipment problem
--    Outer query: all cold buildings (health ALARM, i.e. their substation delivers < 50 °C).
--    Subquery (graph): every asset 1 to 4 open pipes downstream of a pump station
--    with a current anomaly. FLATLINE is left out: a frozen value is a sensor
--    problem, not an equipment problem. Only pump stations count as a cause: the
--    substation anomalies (e.g. SS-05.x) are symptoms of the pump upstream.
--    NOT IN keeps the cold buildings that no faulty pump explains.
--    Expected (incident): the 5 buildings of SS-09.3 in Laufamholz. Their pump
--    PS-09 is fine; SS-09.3 reports exactly 41 °C for 30 minutes (FLATLINE), so
--    the buildings look cold because of a stuck sensor: send a technician to
--    check the sensor, not a repair crew to the pump.
SELECT b.asset_id, b.name, b.district, b.health_reason
FROM   dh_assets b
WHERE  b.asset_type = 'BUILDING' AND b.health_status = 'ALARM'
AND    b.asset_id NOT IN (
         SELECT cold_building
         FROM   GRAPH_TABLE (dh_network
                  MATCH (an IS anomaly WHERE an.status <> 'CLOSED' AND an.anomaly_type <> 'FLATLINE')
                        -[IS detected_on]-> (s IS asset WHERE s.asset_type = 'PUMP_STATION')
                        -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4} (x IS asset)
                  COLUMNS (x.asset_id AS cold_building)))
ORDER  BY b.asset_id;
-- ... and what the substation says about it
SELECT anomaly_type, severity, details FROM dh_anomalies WHERE asset_id = 'SS-09.3' AND status <> 'CLOSED';

-- 7) One row per step: the supply path from the plant to the hospital
SELECT *
FROM   GRAPH_TABLE (dh_network
         MATCH (pl IS asset WHERE pl.asset_type = 'PLANT')
               -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
               (h IS asset WHERE h.building_type = 'HOSPITAL' AND h.asset_id LIKE 'B-05%')
         ONE ROW PER STEP (v1, e, v2)
         -- ELEMENT_NUMBER counts vertices and edges (v=1, e=2, v=3, e=4 ...): edge n is element 2n
         COLUMNS (ELEMENT_NUMBER(e) / 2 AS step, v1.asset_id AS from_asset, e.pipe_id, e.length_m, v2.asset_id AS to_asset))
ORDER  BY step;

-- 8) Everything in one call - the tool the agent uses
SELECT JSON_SERIALIZE(agent_find_root_cause() RETURNING CLOB PRETTY) AS root_cause FROM dual;
