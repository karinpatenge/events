-- =============================================================================
-- 04_property_graphs.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-10-21
--
-- SQL property graphs on top of the relational tables. No data is copied:
-- a property graph is metadata, GRAPH_TABLE reads the live tables.
--
--   DH_NETWORK       assets, anomalies, work orders; pipes in flow direction
--   DH_LIVE_NETWORK  what-if view of the network: only in-service assets and
--                    open pipes, scenario set through context DH_CTX
--   DH_DEPENDENCY    same live network, edges reversed (building depends_on
--                    substation depends_on pump station ...), for PageRank
-- =============================================================================

-- -----------------------------------------------------------------------------
-- What-if scenarios: a context read by the "live" views
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE dh_whatif AS
  -- p_out_of_service: comma separated asset ids, e.g. 'PS-04'
  -- p_open_valves:    comma separated pipe ids,  e.g. 'BYP-1'
  PROCEDURE set_scenario (p_out_of_service IN VARCHAR2 DEFAULT NULL,
                          p_open_valves    IN VARCHAR2 DEFAULT NULL);
  PROCEDURE clear;
END dh_whatif;
/

CREATE OR REPLACE PACKAGE BODY dh_whatif AS
  PROCEDURE set_scenario (p_out_of_service IN VARCHAR2 DEFAULT NULL,
                          p_open_valves    IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    DBMS_SESSION.SET_CONTEXT('DH_CTX', 'OOS',         REPLACE(UPPER(p_out_of_service), ' '));
    DBMS_SESSION.SET_CONTEXT('DH_CTX', 'OPEN_VALVES', REPLACE(UPPER(p_open_valves),    ' '));
  END set_scenario;

  PROCEDURE clear IS
  BEGIN
    DBMS_SESSION.CLEAR_CONTEXT('DH_CTX');
  END clear;
END dh_whatif;
/

CREATE OR REPLACE CONTEXT dh_ctx USING dh_whatif;

CREATE OR REPLACE VIEW dh_assets_live_v AS
SELECT a.asset_id, a.asset_type, a.name, a.district, a.latitude, a.longitude,
       a.apartments, a.building_type, a.criticality, a.health_status
FROM   dh_assets a
WHERE  a.in_service = 'Y'
AND    INSTR(',' || SYS_CONTEXT('DH_CTX', 'OOS') || ',', ',' || a.asset_id || ',') = 0;

CREATE OR REPLACE VIEW dh_pipes_live_v AS
SELECT p.pipe_id, p.from_asset, p.to_asset, p.pipe_kind, p.length_m, p.diameter_mm,
       CASE WHEN INSTR(',' || SYS_CONTEXT('DH_CTX', 'OPEN_VALVES') || ',', ',' || p.pipe_id || ',') > 0
            THEN 'OPEN' ELSE p.valve_state END AS valve_state
FROM   dh_pipes p
WHERE  (p.valve_state = 'OPEN'
        OR INSTR(',' || SYS_CONTEXT('DH_CTX', 'OPEN_VALVES') || ',', ',' || p.pipe_id || ',') > 0)
AND    p.from_asset IN (SELECT asset_id FROM dh_assets_live_v)
AND    p.to_asset   IN (SELECT asset_id FROM dh_assets_live_v);

-- -----------------------------------------------------------------------------
-- 1) The network with its operational context
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROPERTY GRAPH dh_network
  VERTEX TABLES (
    dh_assets
      KEY (asset_id)
      LABEL asset
      PROPERTIES (asset_id, asset_type, name, district, latitude, longitude, install_year,
                  equipment, rated_kw, apartments, building_type, criticality,
                  in_service, health_status, health_reason),
    dh_anomalies
      KEY (anomaly_id)
      LABEL anomaly
      PROPERTIES (anomaly_id, metric, anomaly_type, severity, status, detected_at,
                  observed_value, expected_value, hours_to_alarm, details),
    dh_work_orders
      KEY (wo_id)
      LABEL work_order
      PROPERTIES (wo_id, priority, title, status, created_at, created_by)
  )
  EDGE TABLES (
    dh_pipes
      KEY (pipe_id)
      SOURCE      KEY (from_asset) REFERENCES dh_assets (asset_id)
      DESTINATION KEY (to_asset)   REFERENCES dh_assets (asset_id)
      LABEL supplies
      PROPERTIES (pipe_id, pipe_kind, diameter_mm, length_m, material, install_year, valve_state),
    dh_anomalies AS anomaly_on
      KEY (anomaly_id)
      SOURCE      KEY (anomaly_id) REFERENCES dh_anomalies (anomaly_id)
      DESTINATION KEY (asset_id)   REFERENCES dh_assets (asset_id)
      LABEL detected_on NO PROPERTIES,
    dh_work_orders AS work_order_on
      KEY (wo_id)
      SOURCE      KEY (wo_id)    REFERENCES dh_work_orders (wo_id)
      DESTINATION KEY (asset_id) REFERENCES dh_assets (asset_id)
      LABEL targets NO PROPERTIES
  );

COMMENT ON PROPERTY GRAPH dh_network IS
  'District heating network: assets, pipes (flow direction), anomalies and work orders';

-- -----------------------------------------------------------------------------
-- 2) Live network for what-if analysis (views, scenario from DH_CTX)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROPERTY GRAPH dh_live_network
  VERTEX TABLES (
    dh_assets_live_v
      KEY (asset_id)
      LABEL asset
      PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    dh_pipes_live_v
      KEY (pipe_id)
      SOURCE      KEY (from_asset) REFERENCES dh_assets_live_v (asset_id)
      DESTINATION KEY (to_asset)   REFERENCES dh_assets_live_v (asset_id)
      LABEL supplies
      PROPERTIES ARE ALL COLUMNS
  );

-- -----------------------------------------------------------------------------
-- 3) Dependency view: edges point upstream (who depends on whom)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROPERTY GRAPH dh_dependency
  VERTEX TABLES (
    dh_assets_live_v
      KEY (asset_id)
      LABEL asset
      PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    dh_pipes_live_v
      KEY (pipe_id)
      SOURCE      KEY (to_asset)   REFERENCES dh_assets_live_v (asset_id)
      DESTINATION KEY (from_asset) REFERENCES dh_assets_live_v (asset_id)
      LABEL depends_on
      PROPERTIES (pipe_id, pipe_kind, length_m)
  );

SELECT graph_name, graph_mode FROM user_property_graphs ORDER BY graph_name;
