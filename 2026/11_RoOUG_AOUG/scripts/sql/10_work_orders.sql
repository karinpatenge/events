-- =============================================================================
-- 10_work_orders.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-11-04
--
-- Work orders with a human-in-the-loop workflow in APEX (workflow "Work Order",
-- scripts/apex/BUILD.md):
--
--   NEW ──approve──► PLANNED ──start work──► IN_PROGRESS ──confirm done──► DONE
--     └──reject──► CANCELLED                                (shown as "Closed")
--
-- Every arrow is a task that a person completes in the APEX app. The workflow
-- calls DH_WO_FLOW for each status change. Closing a work order repairs its
-- asset in the simulation (dh_device_sim.repair_asset): the pump runs again, or
-- the stuck sensor works again, and the maintenance history gets an entry.
--
-- Also here, for APEX page 3: DH_BYPASS_FOR_ASSET, the bypass that leads into
-- the area of an asset.
--
-- Run as the demo user after 09_apex_support.sql. Idempotent: the column is
-- only added if missing, everything else is CREATE OR REPLACE.
-- =============================================================================

-- The workflow instance of a work order (NULL until the workflow is started;
-- work orders of the AI agent start without one).
DECLARE
  l_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_n FROM user_tab_columns
  WHERE  table_name = 'DH_WORK_ORDERS' AND column_name = 'WORKFLOW_ID';
  IF l_n = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE dh_work_orders ADD (workflow_id NUMBER)';
  END IF;
END;
/

-- -----------------------------------------------------------------------------
-- What has to be done on an asset, from its type and its open anomalies
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dh_work_plan (p_asset_id IN VARCHAR2) RETURN VARCHAR2 IS
  l_type    dh_assets.asset_type%TYPE;
  l_flat    PLS_INTEGER;
  l_wear    PLS_INTEGER;
  l_stopped PLS_INTEGER;
BEGIN
  SELECT asset_type INTO l_type FROM dh_assets WHERE asset_id = p_asset_id;
  SELECT COUNT(CASE WHEN anomaly_type = 'FLATLINE' THEN 1 END),
         COUNT(CASE WHEN metric IN ('vibration', 'bearing_tmp') THEN 1 END),
         COUNT(CASE WHEN metric IN ('flow', 'pressure') AND severity = 'ALARM' THEN 1 END)
  INTO   l_flat, l_wear, l_stopped
  FROM   dh_anomalies
  WHERE  asset_id = p_asset_id AND status <> 'CLOSED';

  IF l_type = 'PUMP_STATION' THEN
    RETURN CASE
      WHEN l_stopped > 0 THEN
        'The pump has stopped: no flow, no discharge pressure. Replace the worn pump bearing, '
        || 'check the shaft alignment, restart the pump, then check flow, discharge pressure and vibration.'
      WHEN l_wear > 0 THEN
        'Vibration and bearing temperature are rising towards the alarm limit. Inspect the pump bearing '
        || 'and the shaft alignment, replace and lubricate the bearing, check the vibration after the restart.'
      ELSE
        'Inspect the pump station: pumps, bearings, valves and sensors.'
    END;
  ELSIF l_type = 'SUBSTATION' THEN
    RETURN CASE
      WHEN l_flat > 0 THEN
        'The temperature sensor of the secondary supply is stuck (the value does not change). Replace the '
        || 'sensor, compare its reading with a reference thermometer, check that the buildings get heat.'
      ELSE
        'Inspect the substation: heat exchanger, control valve and sensors.'
    END;
  ELSE
    RETURN 'Inspect the asset.';
  END IF;
EXCEPTION WHEN NO_DATA_FOUND THEN
  RETURN NULL;
END dh_work_plan;
/

-- -----------------------------------------------------------------------------
-- Work orders with asset and readable status, for APEX and the workflow
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dh_work_orders_v AS
SELECT w.wo_id,
       w.asset_id,
       a.name                                   AS asset_name,
       a.asset_type,
       CASE a.asset_type WHEN 'PUMP_STATION' THEN 'Pump station'
                         WHEN 'SUBSTATION'   THEN 'Substation'
                         ELSE INITCAP(REPLACE(a.asset_type, '_', ' ')) END AS asset_type_name,
       a.district,
       w.asset_id || ' (' || a.name || ')'      AS asset_label,
       w.priority,
       w.title,
       DBMS_LOB.SUBSTR(w.details, 4000, 1)      AS details,
       w.status,
       CASE w.status WHEN 'NEW'         THEN 'New'
                     WHEN 'PLANNED'     THEN 'Planned'
                     WHEN 'IN_PROGRESS' THEN 'In progress'
                     WHEN 'DONE'        THEN 'Closed'
                     WHEN 'CANCELLED'   THEN 'Cancelled' END AS status_label,
       w.created_at,
       w.created_by,
       w.workflow_id
FROM   dh_work_orders w
JOIN   dh_assets a ON a.asset_id = w.asset_id;

COMMENT ON TABLE dh_work_orders_v IS 'Work orders with asset name and type and a readable status (DONE is shown as Closed)';
COMMENT ON COLUMN dh_work_orders_v.asset_type_name IS 'Pump station or Substation';
COMMENT ON COLUMN dh_work_orders_v.asset_label IS 'Asset id with name, e.g. PS-04 (Pump station Favoriten)';
COMMENT ON COLUMN dh_work_orders_v.details IS 'What has to be done (dh_work_plan when created from APEX)';
COMMENT ON COLUMN dh_work_orders_v.status IS 'NEW, PLANNED, IN_PROGRESS, DONE or CANCELLED';
COMMENT ON COLUMN dh_work_orders_v.status_label IS 'New, Planned, In progress, Closed or Cancelled';
COMMENT ON COLUMN dh_work_orders_v.workflow_id IS 'APEX workflow instance; NULL until the workflow is started';

-- -----------------------------------------------------------------------------
-- The status changes, called by the activities of the APEX workflow
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE dh_wo_flow AS
  -- New work order from APEX (created_by APEX), returns its number. Commits.
  FUNCTION create_work_order (p_asset_id IN VARCHAR2,
                              p_priority IN VARCHAR2,
                              p_title    IN VARCHAR2,
                              p_details  IN VARCHAR2) RETURN NUMBER;
  -- Remembers the workflow instance of a work order. Commits.
  PROCEDURE set_workflow (p_wo_id IN NUMBER, p_workflow_id IN NUMBER);
  -- PLANNED, IN_PROGRESS or CANCELLED; only for a work order that is still open.
  -- No commit: the workflow engine commits the activity.
  PROCEDURE set_status (p_wo_id IN NUMBER, p_status IN VARCHAR2);
  -- DONE ("Closed"), repairs the asset and writes an entry into DH_MAINTENANCE
  -- (id W-<wo_id>). No commit: the workflow engine commits the activity.
  PROCEDURE close_work_order (p_wo_id IN NUMBER);
  -- Suggestions for the APEX page: priority and title from the asset's state
  FUNCTION default_priority (p_asset_id IN VARCHAR2) RETURN VARCHAR2;
  FUNCTION default_title    (p_asset_id IN VARCHAR2) RETURN VARCHAR2;
END dh_wo_flow;
/

CREATE OR REPLACE PACKAGE BODY dh_wo_flow AS

  FUNCTION create_work_order (p_asset_id IN VARCHAR2,
                              p_priority IN VARCHAR2,
                              p_title    IN VARCHAR2,
                              p_details  IN VARCHAR2) RETURN NUMBER IS
    l_json CLOB;
    l_id   NUMBER;
  BEGIN
    -- the same function as the agent tool (autonomous transaction, commits)
    l_json := dh_graph_api.create_work_order(p_asset_id   => p_asset_id,
                                             p_priority   => p_priority,
                                             p_title      => p_title,
                                             p_details    => p_details,
                                             p_created_by => 'APEX');
    l_id := JSON_VALUE(l_json, '$.wo_id' RETURNING NUMBER);
    IF l_id IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, NVL(JSON_VALUE(l_json, '$.error'), 'Work order not created'));
    END IF;
    RETURN l_id;
  END create_work_order;

  PROCEDURE set_workflow (p_wo_id IN NUMBER, p_workflow_id IN NUMBER) IS
  BEGIN
    UPDATE dh_work_orders SET workflow_id = p_workflow_id WHERE wo_id = p_wo_id;
    COMMIT;
  END set_workflow;

  PROCEDURE set_status (p_wo_id IN NUMBER, p_status IN VARCHAR2) IS
  BEGIN
    IF p_status NOT IN ('PLANNED', 'IN_PROGRESS', 'CANCELLED') THEN
      RAISE_APPLICATION_ERROR(-20002, 'Status must be PLANNED, IN_PROGRESS or CANCELLED');
    END IF;
    -- a work order that no longer exists (demo reset) or is already closed is left alone
    UPDATE dh_work_orders SET status = p_status
    WHERE  wo_id = p_wo_id AND status IN ('NEW', 'PLANNED', 'IN_PROGRESS');
  END set_status;

  PROCEDURE close_work_order (p_wo_id IN NUMBER) IS
  BEGIN
    FOR w IN (SELECT wo_id, asset_id, priority, title FROM dh_work_orders
              WHERE  wo_id = p_wo_id AND status IN ('NEW', 'PLANNED', 'IN_PROGRESS')) LOOP
      UPDATE dh_work_orders SET status = 'DONE' WHERE wo_id = w.wo_id;
      dh_device_sim.repair_asset(w.asset_id);              -- the crew's work takes effect
      MERGE INTO dh_maintenance t
      USING (SELECT 'W-' || w.wo_id AS maint_id FROM dual) s
      ON (t.maint_id = s.maint_id)
      WHEN NOT MATCHED THEN
        INSERT (maint_id, asset_id, performed_on, maint_type, description, downtime_hours)
        VALUES (s.maint_id, w.asset_id, SYSDATE,
                CASE w.priority WHEN 'P4' THEN 'INSPECTION' WHEN 'P3' THEN 'PREVENTIVE' ELSE 'CORRECTIVE' END,
                SUBSTR('Work order ' || w.wo_id || ' (' || w.priority || ') closed: ' || w.title, 1, 400),
                NULL);
      dh_device_sim.log_msg('WORK_ORDER', 'Work order ' || w.wo_id || ' closed, ' || w.asset_id || ' repaired');
    END LOOP;
  END close_work_order;

  FUNCTION default_priority (p_asset_id IN VARCHAR2) RETURN VARCHAR2 IS
    l_health dh_assets.health_status%TYPE;
    l_flat   PLS_INTEGER;
  BEGIN
    SELECT health_status INTO l_health FROM dh_assets WHERE asset_id = p_asset_id;
    SELECT COUNT(*) INTO l_flat FROM dh_anomalies
    WHERE  asset_id = p_asset_id AND status <> 'CLOSED' AND anomaly_type = 'FLATLINE';
    RETURN CASE WHEN l_flat > 0           THEN 'P4'     -- suspected sensor fault: check
                WHEN l_health = 'ALARM'   THEN 'P1'     -- people without heat now
                WHEN l_health = 'WARNING' THEN 'P2'     -- failure expected soon
                ELSE 'P3' END;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RETURN 'P3';
  END default_priority;

  FUNCTION default_title (p_asset_id IN VARCHAR2) RETURN VARCHAR2 IS
    l_type dh_assets.asset_type%TYPE;
    l_flat PLS_INTEGER;
  BEGIN
    SELECT asset_type INTO l_type FROM dh_assets WHERE asset_id = p_asset_id;
    SELECT COUNT(*) INTO l_flat FROM dh_anomalies
    WHERE  asset_id = p_asset_id AND status <> 'CLOSED' AND anomaly_type = 'FLATLINE';
    RETURN CASE WHEN l_type = 'PUMP_STATION'    THEN 'Repair pump station ' || p_asset_id
                WHEN l_flat > 0                 THEN 'Replace temperature sensor at substation ' || p_asset_id
                WHEN l_type = 'SUBSTATION'      THEN 'Inspect substation ' || p_asset_id
                ELSE 'Inspect ' || p_asset_id END;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RETURN 'Inspect ' || p_asset_id;
  END default_title;

END dh_wo_flow;
/

-- -----------------------------------------------------------------------------
-- APEX page 3: the bypass that matters for an asset
--   the asset is an end of the bypass, or the bypass leads into the area the
--   asset supplies, or the asset lies behind the end of the bypass.
--   PS-04 -> BYP-1 (PS-06 -> PS-05; PS-05 is supplied by PS-04)
-- Returns the pipe id, or NULL. Topology only (pipes without bypasses, up to
-- 4 hops), independent of the current valve states.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dh_bypass_for_asset (p_asset_id IN VARCHAR2) RETURN VARCHAR2 IS
  l_asset dh_assets.asset_id%TYPE := UPPER(TRIM(p_asset_id));
  l_pipe  dh_pipes.pipe_id%TYPE;
BEGIN
  -- PL/SQL variables must stay outside GRAPH_TABLE (ORA-49028): filter on its output
  SELECT MIN(b.pipe_id) INTO l_pipe
  FROM   dh_pipes b
  WHERE  b.pipe_kind = 'BYPASS'
  AND   (l_asset IN (b.from_asset, b.to_asset)
         OR EXISTS (SELECT 1
                    FROM   GRAPH_TABLE (dh_network
                             MATCH (s IS asset) -[p IS supplies WHERE p.pipe_kind <> 'BYPASS']->{1,4} (d IS asset)
                             COLUMNS (s.asset_id AS up, d.asset_id AS dn)) g
                    WHERE  (g.up = l_asset    AND g.dn = b.to_asset)     -- bypass leads into the asset's area
                    OR     (g.up = b.to_asset AND g.dn = l_asset)));     -- asset lies behind the bypass
  RETURN l_pipe;
END dh_bypass_for_asset;
/

-- Check: PS-04 BYP-1, PS-05 BYP-1, PS-06 BYP-1, SS-04.1 none
SELECT asset_id, dh_bypass_for_asset(asset_id) AS bypass
FROM   dh_assets WHERE asset_id IN ('PS-04', 'PS-05', 'PS-06', 'SS-04.1', 'SS-05.2')
ORDER  BY asset_id;
