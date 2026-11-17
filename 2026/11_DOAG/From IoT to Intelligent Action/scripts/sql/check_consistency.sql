-- =============================================================================
-- check_consistency.sql - checks that the demo is in sync, read-only
--
-- Author:      Karin Patenge
-- Last update: 2026-11-17
--
-- Run as the demo user (GRAPHAI) from the scripts folder in SQLcl, at any time
-- (it changes nothing):
--   @sql/check_consistency.sql
--
-- One list with PASS, FAIL or INFO per check:
--   J  the job DH_TICK_JOB runs (enabled, not overdue, last tick < 60 s ago)
--   S  simulation: every pump station and substation has a state and sends
--      readings; the stuck-sensor setting is valid; posts to the IoT Platform
--   H  health: buildings follow the supply temperature of their substation,
--      pump stations and substations their worst open finding; no duplicate
--      or stale findings
--   W  work orders, APEX workflows and tasks belong together: no open work
--      order without a running workflow, no running workflow or open task
--      without its work order, no second workflow per work order, every work
--      order closed by its workflow has its maintenance entry
-- The J, S and stale-finding checks need the job running; right after a
-- start, wait a minute. Everything is read in one statement, so the checks
-- see one consistent state. What to do on FAIL: see the end of this file.
-- =============================================================================
SET LINESIZE 200
SET PAGESIZE 100
COLUMN id       FORMAT A3
COLUMN check_   FORMAT A80 HEADING 'CHECK'
COLUMN expected FORMAT A10
COLUMN actual   FORMAT A40
COLUMN result   FORMAT A6

WITH now_utc AS (SELECT SYS_EXTRACT_UTC(SYSTIMESTAMP) AS t FROM dual),
cfg AS (SELECT MAX(CASE name WHEN 'SIM_STUCK_SENSOR' THEN value END) AS stuck,
               MAX(CASE name WHEN 'IOT_PUBLISH'      THEN value END) AS publish
        FROM   dh_config),
devices AS (SELECT asset_id FROM dh_assets WHERE asset_type IN ('PUMP_STATION', 'SUBSTATION')),
-- APEX: the apps with the work-order workflow, their workflows and tasks
wf AS (SELECT workflow_id, application_id, state_code,
              TO_NUMBER(detail_pk DEFAULT NULL ON CONVERSION ERROR) AS wo_id,
              CASE WHEN state_code IN ('ACTIVE', 'SUSPENDED', 'FAULTED') THEN 'Y' ELSE 'N' END AS is_open
       FROM   apex_workflows
       WHERE  workflow_def_static_id = 'work-order'),
tasks AS (SELECT t.task_id, TO_NUMBER(t.detail_pk DEFAULT NULL ON CONVERSION ERROR) AS wo_id
          FROM   apex_tasks t
          WHERE  t.application_id IN (SELECT application_id FROM wf)
          AND    t.state_code IN ('UNASSIGNED', 'ASSIGNED')),
wo AS (SELECT wo_id, asset_id, status, workflow_id,
              CASE WHEN status IN ('NEW', 'PLANNED', 'IN_PROGRESS') THEN 'Y' ELSE 'N' END AS is_open
       FROM   dh_work_orders),
-- latest supply temperature per substation, and what the building status should be
t_sec AS (SELECT asset_id, MAX(value) KEEP (DENSE_RANK LAST ORDER BY ts) AS val
          FROM   dh_telemetry
          WHERE  metric = 't_sec' AND ts > (SELECT t FROM now_utc) - INTERVAL '1' DAY
          GROUP  BY asset_id),
bld AS (SELECT b.asset_id, b.health_status,
               CASE WHEN t.val < 50 THEN 'ALARM' WHEN t.val < 55 THEN 'WARNING' ELSE 'OK' END AS expected
        FROM   dh_assets b
        JOIN   dh_pipes p ON p.to_asset = b.asset_id
        JOIN   t_sec t    ON t.asset_id = p.from_asset
        WHERE  b.asset_type = 'BUILDING'),
dev_health AS (SELECT x.asset_id, x.health_status,
                      NVL(DECODE(MAX(DECODE(an.severity, 'ALARM', 3, 'WARNING', 2, 'WATCH', 1)),
                                 3, 'ALARM', 2, 'WARNING', 1, 'WATCH'), 'OK') AS expected
               FROM   dh_assets x
               LEFT   JOIN dh_anomalies an ON an.asset_id = x.asset_id AND an.status <> 'CLOSED'
               WHERE  x.asset_type IN ('PUMP_STATION', 'SUBSTATION')
               GROUP  BY x.asset_id, x.health_status),
checks AS (
  SELECT 'J1' id, 'Job DH_TICK_JOB is enabled' check_, 'TRUE' expected,
         NVL(MAX(enabled), 'missing') actual
  FROM   user_scheduler_jobs WHERE job_name = 'DH_TICK_JOB'
  UNION ALL
  SELECT 'J2', 'Job DH_TICK_JOB is not overdue (next run not more than 60 s in the past)', 'yes',
         NVL(MAX(CASE WHEN state = 'RUNNING' OR next_run_date > SYSTIMESTAMP - INTERVAL '60' SECOND THEN 'yes'
                      ELSE 'no, due since ' || TO_CHAR(next_run_date, 'HH24:MI:SS TZR') END), 'missing')
  FROM   user_scheduler_jobs WHERE job_name = 'DH_TICK_JOB'
  UNION ALL
  SELECT 'J3', 'Last live reading less than 60 s ago', 'yes',
         -- now from a join, not a scalar subquery: next to MAX that raises ORA-00937
         CASE WHEN MAX(r.ts) > MAX(n.t) - INTERVAL '60' SECOND THEN 'yes'
              ELSE 'no, last ' || NVL(TO_CHAR(MAX(r.ts), 'YYYY-MM-DD HH24:MI:SS') || ' UTC', '-') END
  FROM   dh_telemetry r CROSS JOIN now_utc n WHERE r.source <> 'BACKFILL'
  UNION ALL
  SELECT 'S0', 'Pump stations and substations (one digital twin each, data/network.json)', '50', TO_CHAR(COUNT(*))
  FROM   devices
  UNION ALL
  SELECT 'S1', 'Pump stations and substations without simulation state', '0', TO_CHAR(COUNT(*))
  FROM   devices d WHERE NOT EXISTS (SELECT 1 FROM dh_sim_state s WHERE s.asset_id = d.asset_id)
  UNION ALL
  SELECT 'S2', 'Pump stations and substations without a reading in the last 60 s', '0', TO_CHAR(COUNT(*))
  FROM   devices d
  WHERE  NOT EXISTS (SELECT 1 FROM dh_telemetry x
                     WHERE  x.asset_id = d.asset_id AND x.ts > (SELECT t FROM now_utc) - INTERVAL '60' SECOND)
  UNION ALL
  SELECT 'S3', 'Stuck-sensor setting is NONE or an existing substation', 'yes',
         CASE WHEN c.stuck = 'NONE'
                OR EXISTS (SELECT 1 FROM dh_assets a WHERE a.asset_id = c.stuck AND a.asset_type = 'SUBSTATION')
              THEN 'yes' ELSE 'no: ' || NVL(c.stuck, 'not set') END
  FROM   cfg c
  UNION ALL
  SELECT 'S4', 'Devices whose last post to the IoT Platform failed (0 when the posts are off)', '0',
         TO_CHAR(CASE WHEN MAX(c.publish) = 'Y'
                      THEN COUNT(CASE WHEN s.last_http_status NOT BETWEEN 200 AND 299 THEN 1 END) ELSE 0 END)
  FROM   dh_sim_state s CROSS JOIN cfg c
  UNION ALL
  SELECT 'H1', 'Buildings whose status does not follow the supply temperature of their substation', '0',
         TO_CHAR(COUNT(*)) || NVL2(MAX(asset_id), ' (e.g. ' || MAX(asset_id) || ')', NULL)
  FROM   bld WHERE health_status <> expected
  UNION ALL
  SELECT 'H2', 'Pump stations and substations whose status is not their worst open finding', '0',
         TO_CHAR(COUNT(*)) || NVL2(MAX(asset_id), ' (e.g. ' || MAX(asset_id) || ')', NULL)
  FROM   dev_health WHERE health_status <> expected
  UNION ALL
  SELECT 'H3', 'Duplicate open findings (same asset, metric and type)', '0', TO_CHAR(COUNT(*))
  FROM  (SELECT asset_id FROM dh_anomalies WHERE status <> 'CLOSED'
         GROUP BY asset_id, metric, anomaly_type HAVING COUNT(*) > 1)
  UNION ALL
  SELECT 'H4', 'Open findings not seen for more than 90 s (they should be closed)', '0', TO_CHAR(COUNT(*))
  FROM   dh_anomalies
  WHERE  status <> 'CLOSED' AND last_seen_at < (SELECT t FROM now_utc) - INTERVAL '90' SECOND
  UNION ALL
  SELECT 'W1', 'Open work orders whose workflow has ended or is missing', '0',
         TO_CHAR(COUNT(*)) || NVL2(MAX(w.wo_id), ' (e.g. ' || MAX(w.wo_id) || ')', NULL)
  FROM   wo w
  WHERE  w.is_open = 'Y' AND w.workflow_id IS NOT NULL
  AND    NOT EXISTS (SELECT 1 FROM wf f WHERE f.workflow_id = w.workflow_id AND f.is_open = 'Y')
  UNION ALL
  SELECT 'W2', 'Closed or cancelled work orders whose workflow is still running', '0',
         TO_CHAR(COUNT(*)) || NVL2(MAX(w.wo_id), ' (e.g. ' || MAX(w.wo_id) || ')', NULL)
  FROM   wo w
  WHERE  w.is_open = 'N' AND EXISTS (SELECT 1 FROM wf f WHERE f.wo_id = w.wo_id AND f.is_open = 'Y')
  UNION ALL
  SELECT 'W3', 'Running workflows without their work order', '0',
         TO_CHAR(COUNT(*)) || NVL2(MAX(f.workflow_id), ' (e.g. ' || MAX(f.workflow_id) || ')', NULL)
  FROM   wf f WHERE f.is_open = 'Y' AND NOT EXISTS (SELECT 1 FROM wo w WHERE w.wo_id = f.wo_id)
  UNION ALL
  SELECT 'W4', 'Open tasks without their work order', '0',
         TO_CHAR(COUNT(*)) || NVL2(MAX(t.task_id), ' (e.g. task ' || MAX(t.task_id) || ')', NULL)
  FROM   tasks t WHERE NOT EXISTS (SELECT 1 FROM wo w WHERE w.wo_id = t.wo_id)
  UNION ALL
  SELECT 'W5', 'Open tasks of a closed or cancelled work order', '0',
         TO_CHAR(COUNT(*)) || NVL2(MAX(t.task_id), ' (e.g. task ' || MAX(t.task_id) || ')', NULL)
  FROM   tasks t JOIN wo w ON w.wo_id = t.wo_id WHERE w.is_open = 'N'
  UNION ALL
  SELECT 'W6', 'Work orders with more than one running workflow', '0', TO_CHAR(COUNT(*))
  FROM  (SELECT wo_id FROM wf WHERE is_open = 'Y' AND wo_id IS NOT NULL GROUP BY wo_id HAVING COUNT(*) > 1)
  UNION ALL
  SELECT 'W7', 'Open work orders whose WORKFLOW_ID points to another work order''s workflow', '0',
         TO_CHAR(COUNT(*)) || NVL2(MAX(w.wo_id), ' (e.g. ' || MAX(w.wo_id) || ')', NULL)
  FROM   wo w
  WHERE  w.is_open = 'Y' AND w.workflow_id IS NOT NULL
  AND    EXISTS (SELECT 1 FROM wf f WHERE f.workflow_id = w.workflow_id)
  AND    NOT EXISTS (SELECT 1 FROM wf f WHERE f.workflow_id = w.workflow_id AND f.wo_id = w.wo_id)
  UNION ALL
  SELECT 'W8', 'Work orders closed by their workflow without maintenance entry W-<id>', '0',
         TO_CHAR(COUNT(*)) || NVL2(MAX(w.wo_id), ' (e.g. ' || MAX(w.wo_id) || ')', NULL)
  FROM   wo w
  WHERE  w.status = 'DONE' AND w.workflow_id IS NOT NULL
  AND    NOT EXISTS (SELECT 1 FROM dh_maintenance m WHERE m.maint_id = 'W-' || w.wo_id)
  UNION ALL
  SELECT 'W9', 'Open work orders without a workflow (AI agent; started on page 6)', 'info',
         TO_CHAR(COUNT(*)) || NVL2(MAX(w.wo_id), ' (e.g. ' || MAX(w.wo_id) || ')', NULL)
  FROM   wo w WHERE w.is_open = 'Y' AND w.workflow_id IS NULL
)
-- TRIM: the literals of the UNION ALL come back blank-padded to the longest one
SELECT TRIM(id) AS id, TRIM(check_) AS check_, TRIM(expected) AS expected, actual,
       CASE WHEN TRIM(expected) = 'info' THEN 'INFO'
            WHEN REGEXP_SUBSTR(actual, '^\S+') = TRIM(expected) THEN 'PASS'
            ELSE 'FAIL' END AS result
FROM   checks
ORDER  BY INSTR('JSHW', SUBSTR(id, 1, 1)), id;   -- job, simulation, health, work orders

-- What to do on FAIL
--   J1-J3, S2, H4   the job is off or stalled: @sql/stop_tick_job.sql, then
--                   EXEC dh_job_tick and EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')
--   S1              EXEC dh_job_tick (creates the missing state rows)
--   S3              EXEC dh_device_sim.reset (puts the stuck sensor back on SS-09.3)
--   S4              SELECT dh_device_sim.status FROM dual; @sql/iot_publish.sql off if the
--                   IoT Platform is not reachable
--   H1-H3           EXEC dh_job_tick; if it stays: @sql/demo_state.sql
--   W1-W8           @sql/apex_cleanup.sql (ends all open work-order workflows and tasks),
--                   or @sql/demo_state.sql for a full reset
