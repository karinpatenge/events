-- =============================================================================
-- 09_apex_support.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-11-03
--
-- Views and small procedures used by the APEX application "Heat Network Ops".
-- Region queries for the Graph Visualization plug-in are in scripts/apex/BUILD.md.
-- DH_ANALYSIS_V (at the end) is the curated view for the optional Data Analysis
-- Agent of the Private Agent Factory (scripts/README.md, section 8.4).
-- =============================================================================

-- Colours for the Map Region and cards, the same as in the graph styles
-- (scripts/apex/BUILD.md): health problem -> health colour, else the colour
-- of the asset type. The map layers use them as &HEALTH_COLOR. and &TYPE_COLOR.
CREATE OR REPLACE VIEW dh_asset_status_v AS
SELECT a.asset_id, a.asset_type, a.name, a.district, a.latitude, a.longitude,
       a.apartments, a.building_type, a.criticality, a.in_service,
       a.health_status, a.health_reason, a.health_updated,
       DECODE(a.asset_type, 'PLANT', 'Heat plant', 'PUMP_STATION', 'Pump station',
                            'SUBSTATION', 'Substation', 'Building') AS type_name,
       DECODE(a.asset_type, 'PLANT', '#8E44AD', 'PUMP_STATION', '#2C3E50',
                            'SUBSTATION', '#8D6E63', '#7FA65F') AS type_color,
       CASE a.health_status WHEN 'ALARM' THEN '#C74634' WHEN 'WARNING' THEN '#F0AB00'
                            WHEN 'WATCH' THEN '#D63384'
            ELSE DECODE(a.asset_type, 'PLANT', '#8E44AD', 'PUMP_STATION', '#2C3E50',
                                      'SUBSTATION', '#8D6E63', '#7FA65F') END AS health_color,
       DECODE(a.health_status, 'ALARM', 3, 'WARNING', 2, 'WATCH', 1, 0)     AS health_rank,
       SDO_GEOMETRY(2001, 4326, SDO_POINT_TYPE(a.longitude, a.latitude, NULL), NULL, NULL) AS geom
FROM   dh_assets a;

-- Pipes as lines for the APEX Map Region; LINE_COLOR for the stroke colour
-- (&LINE_COLOR.): pipes grey, closed bypass light blue, open bypass green.
-- TO_ASSET_TYPE lets the map hide the pipes to buildings (switch P2_SHOW_BUILDINGS).
CREATE OR REPLACE VIEW dh_pipe_lines_v AS
SELECT p.pipe_id, p.pipe_kind, p.valve_state, p.diameter_mm, p.length_m,
       p.from_asset, p.to_asset, t.asset_type AS to_asset_type,
       CASE WHEN p.pipe_kind <> 'BYPASS' THEN '#9B9B9B'
            WHEN p.valve_state = 'CLOSED' THEN '#5F96AE' ELSE '#7FA65F' END AS line_color,
       SDO_GEOMETRY(2002, 4326, NULL, SDO_ELEM_INFO_ARRAY(1, 2, 1),
                    SDO_ORDINATE_ARRAY(f.longitude, f.latitude, t.longitude, t.latitude)) AS geom
FROM   dh_pipes p
JOIN   dh_assets f ON f.asset_id = p.from_asset
JOIN   dh_assets t ON t.asset_id = p.to_asset;

-- Last 6 hours of telemetry, session time zone (APEX: enable Automatic Time Zone)
CREATE OR REPLACE VIEW dh_telemetry_recent_v AS
SELECT t.asset_id, t.metric, m.display_name, m.unit,
       CAST(FROM_TZ(t.ts, 'UTC') AT LOCAL AS TIMESTAMP) AS ts_local,
       t.value, m.warn_high, m.alarm_high, m.warn_low, m.alarm_low, t.source
FROM   dh_telemetry t
JOIN   dh_assets  a ON a.asset_id = t.asset_id
JOIN   dh_metrics m ON m.asset_type = a.asset_type AND m.metric = t.metric
WHERE  t.ts > SYS_EXTRACT_UTC(SYSTIMESTAMP) - INTERVAL '6' HOUR;

-- Open anomalies with asset context (report + cards). ANOMALY_TYPE_NAME and
-- ANOMALY_CLASS (CSS class, one background colour per type) for the APEX cards.
CREATE OR REPLACE VIEW dh_open_anomalies_v AS
SELECT an.anomaly_id, an.asset_id, a.name AS asset_name, a.asset_type, a.district,
       an.metric, an.anomaly_type, an.severity, an.details, an.hours_to_alarm,
       DECODE(an.anomaly_type, 'THRESHOLD', 'Limit exceeded', 'ZSCORE', 'Unusual value',
                               'TREND', 'Trend towards the limit', 'FLATLINE', 'Value frozen',
                               'NO_DATA', 'No data') AS anomaly_type_name,
       'dh-anom-' || LOWER(REPLACE(an.anomaly_type, '_', '-')) AS anomaly_class,
       CAST(FROM_TZ(an.detected_at, 'UTC') AT LOCAL AS TIMESTAMP) AS detected_local
FROM   dh_anomalies an
JOIN   dh_assets a ON a.asset_id = an.asset_id
WHERE  an.status <> 'CLOSED';

-- Operator actions from APEX. The device simulation (06b_device_sim.sql) reads
-- valve_state at every tick, so opening BYP-1 here restores the supply.
CREATE OR REPLACE PROCEDURE dh_set_valve (p_pipe_id IN VARCHAR2, p_state IN VARCHAR2) IS
BEGIN
  UPDATE dh_pipes SET valve_state = UPPER(p_state) WHERE pipe_id = UPPER(p_pipe_id) AND pipe_kind = 'BYPASS';
  COMMIT;
END dh_set_valve;
/

CREATE OR REPLACE PROCEDURE dh_set_in_service (p_asset_id IN VARCHAR2, p_in_service IN VARCHAR2) IS
BEGIN
  UPDATE dh_assets SET in_service = UPPER(p_in_service) WHERE asset_id = UPPER(p_asset_id);
  COMMIT;
END dh_set_in_service;
/

-- Curated view for the Data Analysis Agent (Private Agent Factory). The agent
-- works on one table or view, so this view combines DH_ASSET_STATUS_V and
-- DH_OPEN_ANOMALIES_V: one row per asset with the counts of its open anomalies.
-- No colours, no geometry, readable values. The comments help the agent (and
-- anyone else) understand the columns. APARTMENTS_WITHOUT_HEAT exists so that
-- a sum is self-explaining in the result: the agent's explanation step sees
-- only the result columns, not the WHERE clause.
CREATE OR REPLACE VIEW dh_analysis_v AS
SELECT s.asset_id,
       s.type_name                                          AS asset_type,
       s.name                                               AS asset_name,
       s.district,
       INITCAP(REPLACE(s.building_type, '_', ' '))          AS building_type,
       s.apartments,
       s.criticality,
       CASE WHEN s.asset_type = 'BUILDING' AND s.criticality >= 4
            THEN 'Y' ELSE 'N' END                           AS life_critical,
       s.in_service,
       s.health_status,
       s.health_reason,
       CASE WHEN s.asset_type = 'BUILDING' AND s.health_status = 'ALARM'
            THEN 'Y' ELSE 'N' END                           AS without_heat,
       CASE WHEN s.asset_type = 'BUILDING' AND s.health_status = 'ALARM'
            THEN s.apartments ELSE 0 END                    AS apartments_without_heat,
       NVL(an.open_anomalies, 0)                            AS open_anomalies,
       NVL(an.alarm_anomalies, 0)                           AS alarm_anomalies,
       NVL(an.warning_anomalies, 0)                         AS warning_anomalies,
       NVL(an.watch_anomalies, 0)                           AS watch_anomalies,
       an.anomaly_types,
       an.hours_to_alarm,
       s.latitude,
       s.longitude
FROM   dh_asset_status_v s
LEFT JOIN (SELECT asset_id,
                  COUNT(*)                                          AS open_anomalies,
                  COUNT(CASE WHEN severity = 'ALARM'   THEN 1 END)  AS alarm_anomalies,
                  COUNT(CASE WHEN severity = 'WARNING' THEN 1 END)  AS warning_anomalies,
                  COUNT(CASE WHEN severity = 'WATCH'   THEN 1 END)  AS watch_anomalies,
                  LISTAGG(DISTINCT anomaly_type_name, ', ')
                    WITHIN GROUP (ORDER BY anomaly_type_name)       AS anomaly_types,
                  MIN(hours_to_alarm)                               AS hours_to_alarm
           FROM   dh_open_anomalies_v
           GROUP  BY asset_id) an
       ON an.asset_id = s.asset_id;

COMMENT ON TABLE dh_analysis_v IS
  'District heating network: one row per asset (heat plant, pump station, substation, building) with its health and open anomalies';
COMMENT ON COLUMN dh_analysis_v.asset_id          IS 'Asset id, for example PS-04 (pump station), SS-09.3 (substation), B-09.3.1 (building)';
COMMENT ON COLUMN dh_analysis_v.asset_type        IS 'Heat plant, Pump station, Substation or Building';
COMMENT ON COLUMN dh_analysis_v.asset_name        IS 'Name of the asset';
COMMENT ON COLUMN dh_analysis_v.district          IS 'City district';
COMMENT ON COLUMN dh_analysis_v.building_type     IS 'Buildings only: Residential, Hospital, Nursing Home or School';
COMMENT ON COLUMN dh_analysis_v.apartments        IS 'Buildings only: number of apartments';
COMMENT ON COLUMN dh_analysis_v.criticality       IS '1 low to 5 life-critical';
COMMENT ON COLUMN dh_analysis_v.life_critical     IS 'Y for hospitals, nursing homes and schools (buildings with criticality 4 or 5)';
COMMENT ON COLUMN dh_analysis_v.in_service        IS 'Y if the asset is in service, N if taken out of service';
COMMENT ON COLUMN dh_analysis_v.health_status     IS 'OK, WATCH, WARNING or ALARM (ALARM is the worst)';
COMMENT ON COLUMN dh_analysis_v.health_reason     IS 'Why the asset is not OK';
COMMENT ON COLUMN dh_analysis_v.without_heat      IS 'Y if the building has no heat (building in ALARM)';
COMMENT ON COLUMN dh_analysis_v.apartments_without_heat IS 'Apartments without heat: APARTMENTS of a building without heat, else 0. SUM gives the apartments without heat';
COMMENT ON COLUMN dh_analysis_v.open_anomalies    IS 'Number of open anomalies on the asset';
COMMENT ON COLUMN dh_analysis_v.alarm_anomalies   IS 'Open anomalies with severity ALARM';
COMMENT ON COLUMN dh_analysis_v.warning_anomalies IS 'Open anomalies with severity WARNING';
COMMENT ON COLUMN dh_analysis_v.watch_anomalies   IS 'Open anomalies with severity WATCH';
COMMENT ON COLUMN dh_analysis_v.anomaly_types     IS 'Kinds of open anomalies: Limit exceeded, Unusual value, Trend towards the limit, Value frozen, No data';
COMMENT ON COLUMN dh_analysis_v.hours_to_alarm    IS 'Trend anomalies: hours until the alarm limit is reached';
COMMENT ON COLUMN dh_analysis_v.latitude          IS 'Latitude (WGS84)';
COMMENT ON COLUMN dh_analysis_v.longitude         IS 'Longitude (WGS84)';
