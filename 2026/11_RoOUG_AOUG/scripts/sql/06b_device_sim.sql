-- =============================================================================
-- 06b_device_sim.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-11-04
--
-- Package DH_DEVICE_SIM: the database plays the 50 field devices.
-- Called by the scheduler job DH_TICK_JOB (08_jobs.sql) every 30 seconds:
--
--   1. state      PS-04 tripped? bypass BYP-1 open? Which substations still get
--                 heat? (reachability from the heat plants along open pipes,
--                 through running pump stations; recursive SQL)
--   2. readings   one reading per twin (10 pump stations, 40 substations) from
--                 the same formulas as the 7-day history in 03_backfill.sql:
--                 daily load profile, noise, bearing wear of PS-04 and PS-08,
--                 stuck temperature sensor at SS-09.3 (DH_CONFIG SIM_STUCK_SENSOR)
--   3. store      INSERT into DH_TELEMETRY (source SIMULATED)  - INGEST_MODE DIRECT
--   4. publish    HTTPS POST of the same JSON to the OCI IoT Platform device
--                 endpoint, like a real device (basic auth: external key + device
--                 password), with APEX_WEB_SERVICE    - IOT_PUBLISH = Y
--
-- Operator and demo actions (instead of keys in a simulator):
--   EXEC dh_device_sim.trip('PS-04')        vibration spike, trips at the next tick
--   EXEC dh_device_sim.repair('PS-04')      repaired and restarted, wear gone, open work orders done
--                                           (a closed work order repairs its asset the same way, 10_work_orders.sql)
--   EXEC dh_set_valve('BYP-1', 'OPEN')      bypass (also the APEX button), 09_apex_support.sql
--   EXEC dh_device_sim.reset                simulation state only (dh_sim.reset_state resets all)
--   SELECT dh_device_sim.status FROM dual;  one line: stopped pumps, bypasses, supply, publish
--   EXEC dh_device_sim.publish_test('PS-04')  one test POST, prints HTTP status and response
--
-- Settings in DH_CONFIG (01_schema.sql): SIM_ENABLED, INGEST_MODE, IOT_PUBLISH,
-- IOT_DEVICE_HOST, IOT_DEVICE_ENDPOINT, IOT_DEVICE_PASSWORD.
-- Outbound HTTPS uses APEX_WEB_SERVICE, which needs no network ACL in
-- Autonomous AI Database (see 00_admin_setup.sql).
-- Idempotent: CREATE OR REPLACE, and the setting below is only added if missing.
-- =============================================================================

-- The substation whose temperature sensor is stuck at 41 degrees C. A repair of that
-- substation sets it to NONE; dh_sim.reset_state sets it back to SS-09.3.
MERGE INTO dh_config c USING (SELECT 'SIM_STUCK_SENSOR' name, 'SS-09.3' value FROM dual) s
ON (c.name = s.name) WHEN NOT MATCHED THEN INSERT (name, value) VALUES (s.name, s.value);
COMMIT;

CREATE OR REPLACE PACKAGE dh_device_sim AS
  -- One simulation step: state, readings, store and/or publish. Commits.
  PROCEDURE tick;
  -- Demo actions
  PROCEDURE trip   (p_asset_id IN VARCHAR2 DEFAULT 'PS-04');
  -- repair: the crew's work is done. Restarts the pump (no wear), sets the open
  -- work orders of the asset to DONE and writes an entry into DH_MAINTENANCE
  -- (id R-..., removed again by dh_sim.reset_state). Commits.
  PROCEDURE repair (p_asset_id IN VARCHAR2 DEFAULT 'PS-04');
  -- The effect of a repair on the simulated device only, without commit and
  -- without touching work orders: pump running again, no wear; for the
  -- substation with the stuck sensor, the sensor works again.
  -- Used by repair and by dh_wo_flow.close_work_order (10_work_orders.sql).
  PROCEDURE repair_asset (p_asset_id IN VARCHAR2);
  PROCEDURE reset;
  -- One line about the current simulation state
  FUNCTION  status RETURN VARCHAR2;
  -- Sends one reading with normal values for one twin and prints the result
  PROCEDURE publish_test (p_asset_id IN VARCHAR2 DEFAULT 'PS-04');
  -- Writes a line into DH_JOB_LOG (keeps one day), used by the job as well
  PROCEDURE log_msg (p_step IN VARCHAR2, p_message IN VARCHAR2);
END dh_device_sim;
/

CREATE OR REPLACE PACKAGE BODY dh_device_sim AS

  c_wear_rate_ps04 CONSTANT NUMBER := 0.11;    -- mm/s per hour, as at the end of the backfill
  c_wear_rate_ps08 CONSTANT NUMBER := 0.018;
  -- Time constants, compressed for the demo: after one 30-s step 63 % of the
  -- change is done, after two steps 86 % (buildings react within ~1.5 min)
  c_tau_down       CONSTANT NUMBER := 30;      -- seconds: cooling when supply is lost
  c_tau_up         CONSTANT NUMBER := 30;      -- seconds: recovery

  TYPE t_reading IS RECORD (asset_id VARCHAR2(20), metric VARCHAR2(30), value NUMBER);
  TYPE t_readings IS TABLE OF t_reading INDEX BY PLS_INTEGER;
  TYPE t_body IS RECORD (asset_id VARCHAR2(20), body VARCHAR2(4000));
  TYPE t_bodies IS TABLE OF t_body INDEX BY PLS_INTEGER;

  -- ---------------------------------------------------------------------------
  FUNCTION cfg (p_name IN VARCHAR2) RETURN VARCHAR2 IS
    l_value dh_config.value%TYPE;
  BEGIN
    SELECT value INTO l_value FROM dh_config WHERE name = p_name;
    RETURN l_value;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
  END cfg;

  PROCEDURE set_cfg (p_name IN VARCHAR2, p_value IN VARCHAR2) IS
  BEGIN
    MERGE INTO dh_config c USING (SELECT p_name AS name, p_value AS value FROM dual) s
    ON (c.name = s.name)
    WHEN MATCHED THEN UPDATE SET c.value = s.value
    WHEN NOT MATCHED THEN INSERT (name, value) VALUES (s.name, s.value);
  END set_cfg;

  FUNCTION utc_now RETURN TIMESTAMP IS
    l_ts TIMESTAMP(3);
  BEGIN
    SELECT CAST(SYS_EXTRACT_UTC(SYSTIMESTAMP) AS TIMESTAMP(3)) INTO l_ts FROM dual;   -- in SQL, not in PL/SQL
    RETURN l_ts;
  END utc_now;

  FUNCTION seconds_between (p_from IN TIMESTAMP, p_to IN TIMESTAMP) RETURN NUMBER IS
    l_iv INTERVAL DAY(9) TO SECOND(3) := p_to - p_from;
  BEGIN
    RETURN EXTRACT(DAY FROM l_iv) * 86400 + EXTRACT(HOUR FROM l_iv) * 3600
         + EXTRACT(MINUTE FROM l_iv) * 60 + EXTRACT(SECOND FROM l_iv);
  END seconds_between;

  FUNCTION b64 (p_text IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN REPLACE(REPLACE(UTL_RAW.CAST_TO_VARCHAR2(
             UTL_ENCODE.BASE64_ENCODE(UTL_RAW.CAST_TO_RAW(p_text))), CHR(13)), CHR(10));
  END b64;

  -- Daily heating load, same profile as the backfill (hour of day in UTC+1)
  FUNCTION load_profile (p_ts IN TIMESTAMP) RETURN NUMBER IS
    l_pi  CONSTANT NUMBER := ACOS(-1);
    l_hod NUMBER := MOD(EXTRACT(HOUR FROM p_ts) + 1 + EXTRACT(MINUTE FROM p_ts) / 60, 24);
  BEGIN
    RETURN 0.80 + 0.12 * COS(2 * l_pi * (l_hod - 7) / 24) + 0.05 * COS(2 * l_pi * (l_hod - 19) / 12);
  END load_profile;

  -- ---------------------------------------------------------------------------
  PROCEDURE log_msg (p_step IN VARCHAR2, p_message IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO dh_job_log (step, message) VALUES (SUBSTRB(p_step, 1, 30), SUBSTRB(p_message, 1, 4000));
    DELETE FROM dh_job_log WHERE logged_at < SYSTIMESTAMP - INTERVAL '1' DAY;
    COMMIT;
  END log_msg;

  -- One state row per twin; wear starts where the 7-day history ends
  PROCEDURE ensure_state IS
  BEGIN
    MERGE INTO dh_sim_state s
    USING (SELECT asset_id FROM dh_assets WHERE asset_type IN ('PUMP_STATION', 'SUBSTATION')) a
    ON (s.asset_id = a.asset_id)
    WHEN NOT MATCHED THEN INSERT (asset_id, pump_state, wear, supply)
      VALUES (a.asset_id, 'RUNNING',
              CASE a.asset_id WHEN 'PS-04' THEN 4.4 WHEN 'PS-08' THEN 2.2 ELSE 0 END, 1);
  END ensure_state;

  -- ---------------------------------------------------------------------------
  -- HTTPS POST of one JSON reading to the IoT Platform device endpoint.
  -- Returns the HTTP status; -1 if the call itself failed.
  FUNCTION post_reading (p_asset_id IN VARCHAR2, p_body IN VARCHAR2,
                         p_url IN VARCHAR2, p_password IN VARCHAR2,
                         p_response OUT VARCHAR2) RETURN NUMBER IS
    l_resp CLOB;
  BEGIN
    APEX_WEB_SERVICE.CLEAR_REQUEST_HEADERS;
    APEX_WEB_SERVICE.SET_REQUEST_HEADERS(
      p_name_01  => 'Content-Type',  p_value_01 => 'application/json',
      p_name_02  => 'Authorization', p_value_02 => 'Basic ' || b64(p_asset_id || ':' || p_password));
    l_resp := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
                p_url              => p_url,
                p_http_method      => 'POST',
                p_body             => p_body,
                p_transfer_timeout => 10);
    p_response := DBMS_LOB.SUBSTR(l_resp, 300, 1);
    RETURN APEX_WEB_SERVICE.G_STATUS_CODE;
  EXCEPTION WHEN OTHERS THEN
    p_response := SUBSTR(SQLERRM, 1, 300);
    RETURN -1;
  END post_reading;

  FUNCTION device_url RETURN VARCHAR2 IS
  BEGIN
    RETURN 'https://' || cfg('IOT_DEVICE_HOST') || NVL(cfg('IOT_DEVICE_ENDPOINT'), '/dh/telemetry');
  END device_url;

  FUNCTION publish_ready (p_reason OUT VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    IF cfg('IOT_DEVICE_HOST') IS NULL OR INSTR(cfg('IOT_DEVICE_HOST'), '<') > 0 THEN
      p_reason := 'IOT_DEVICE_HOST is not set';
    ELSIF dh_secret.get_secret('IOT_DEVICE_PASSWORD') IS NULL THEN
      p_reason := 'IOT_DEVICE_PASSWORD is not set';
    END IF;
    RETURN p_reason IS NULL;
  END publish_ready;

  -- ---------------------------------------------------------------------------
  PROCEDURE tick IS
    l_now      TIMESTAMP(3) := utc_now;
    l_last     TIMESTAMP(3);
    l_dt       NUMBER := 30;
    l_load     NUMBER;
    l_ts_txt   VARCHAR2(30);
    l_mode     VARCHAR2(20) := NVL(cfg('INGEST_MODE'), 'DIRECT');
    l_store    BOOLEAN;
    l_publish  BOOLEAN;
    l_reason   VARCHAR2(200);
    l_rd       t_readings;
    l_bd       t_bodies;
    l_n        PLS_INTEGER := 0;
    l_body     VARCHAR2(4000);
    l_url      VARCHAR2(1000);
    l_pwd      VARCHAR2(4000);
    l_status   NUMBER;
    l_resp     VARCHAR2(400);
    l_ok       PLS_INTEGER := 0;
    l_err      PLS_INTEGER := 0;
    l_last_err VARCHAR2(400);
    -- values of one twin
    v_vib NUMBER; v_brg NUMBER; v_pow NUMBER; v_flow NUMBER; v_pres NUMBER;
    v_tsup NUMBER; v_tret NUMBER; v_tsec NUMBER; v_dp NUMBER;
    l_s    NUMBER;
    l_stuck VARCHAR2(20) := NVL(cfg('SIM_STUCK_SENSOR'), 'NONE');   -- substation with the stuck sensor

    PROCEDURE add_reading (p_asset_id IN VARCHAR2, p_metric IN VARCHAR2, p_value IN NUMBER) IS
    BEGIN
      l_n := l_n + 1;
      l_rd(l_n).asset_id := p_asset_id;
      l_rd(l_n).metric   := p_metric;
      l_rd(l_n).value    := ROUND(p_value, 3);
    END add_reading;
  BEGIN
    l_store   := l_mode = 'DIRECT';
    l_publish := cfg('IOT_PUBLISH') = 'Y' OR l_mode = 'IOT';

    -- elapsed time since the last tick (capped, so a long pause does not jump)
    BEGIN
      l_last := TO_TIMESTAMP(cfg('SIM_LAST_TICK'), 'YYYY-MM-DD"T"HH24:MI:SS.FF3');
      IF l_last IS NOT NULL THEN
        l_dt := LEAST(GREATEST(seconds_between(l_last, l_now), 1), 300);
      END IF;
    EXCEPTION WHEN OTHERS THEN l_dt := 30;
    END;
    l_load   := load_profile(l_now);
    -- 6 fractional digits (14:35:26.175000Z): the IoT Platform rejects 3 digits (REJECTED_DATA "could not be parsed at index 20")
    l_ts_txt := TO_CHAR(l_now, 'YYYY-MM-DD"T"HH24:MI:SS.FF6"Z"');

    ensure_state;

    -- 1. state: a requested trip shows a vibration spike for one tick, then the pump stops
    UPDATE dh_sim_state SET pump_state = 'STOPPED'    WHERE pump_state = 'SPIKE_SENT';
    UPDATE dh_sim_state
    SET    wear = wear + CASE asset_id WHEN 'PS-04' THEN c_wear_rate_ps04 ELSE c_wear_rate_ps08 END * l_dt / 3600
    WHERE  asset_id IN ('PS-04', 'PS-08') AND pump_state <> 'STOPPED';

    -- supply: reachable from a heat plant along open pipes; a stopped pump station
    -- is reached, but passes no heat on. Supply follows the target exponentially.
    MERGE INTO dh_sim_state t
    USING (
      WITH usable AS (
        SELECT p.from_asset, p.to_asset
        FROM   dh_pipes p
        WHERE  p.valve_state = 'OPEN'
        AND    p.from_asset NOT IN (SELECT asset_id FROM dh_sim_state WHERE pump_state = 'STOPPED')
      ), reach (asset_id) AS (
        SELECT asset_id FROM dh_assets WHERE asset_type = 'PLANT'
        UNION ALL
        SELECT up.to_asset FROM reach r JOIN usable up ON up.from_asset = r.asset_id
      ) CYCLE asset_id SET is_cycle TO 'Y' DEFAULT 'N'
      SELECT s.asset_id,
             CASE WHEN s.pump_state = 'STOPPED' THEN 0
                  WHEN EXISTS (SELECT 1 FROM reach x WHERE x.asset_id = s.asset_id) THEN 1
                  ELSE 0 END AS target
      FROM   dh_sim_state s
    ) u
    ON (t.asset_id = u.asset_id)
    WHEN MATCHED THEN UPDATE SET
      t.supply = u.target + (t.supply - u.target)
                 * EXP(-l_dt / CASE WHEN u.target > t.supply THEN c_tau_up ELSE c_tau_down END);

    -- 2. readings
    FOR r IN (SELECT s.asset_id, s.pump_state, s.wear, s.supply, a.asset_type, a.rated_kw
              FROM   dh_sim_state s JOIN dh_assets a ON a.asset_id = s.asset_id
              ORDER  BY s.asset_id) LOOP
      l_s := r.supply;
      IF r.asset_type = 'PUMP_STATION' THEN
        IF r.pump_state = 'STOPPED' THEN
          v_vib  := 0.3 + 0.05 * DBMS_RANDOM.NORMAL;
          v_brg  := 88 - 10 * (1 - l_s);
          v_pow  := 4 + 0.5 * DBMS_RANDOM.NORMAL;
          v_flow := 30 + 5 * DBMS_RANDOM.NORMAL;
          v_pres := 1.8 + 0.05 * DBMS_RANDOM.NORMAL;
        ELSE
          v_vib  := 2.0 + 0.1 * l_load + 0.12 * DBMS_RANDOM.NORMAL + r.wear
                    + CASE WHEN r.pump_state = 'SPIKE' THEN 3.5 ELSE 0 END;
          v_brg  := 46 + 8 * l_load + 0.6 * DBMS_RANDOM.NORMAL
                    + r.wear * CASE r.asset_id WHEN 'PS-04' THEN 26 / 4.4 WHEN 'PS-08' THEN 9 / 2.2 ELSE 0 END
                    + CASE WHEN r.pump_state = 'SPIKE' THEN 8 ELSE 0 END;
          v_pow  := r.rated_kw * (0.55 + 0.35 * l_load) * (1 + 0.01 * DBMS_RANDOM.NORMAL);
          v_flow := 1000 * l_load * (0.1 + 0.9 * l_s) + 15 * DBMS_RANDOM.NORMAL;
          v_pres := (9.3 + 0.4 * l_load) * (0.35 + 0.65 * l_s) + 0.05 * DBMS_RANDOM.NORMAL;
        END IF;
        add_reading(r.asset_id, 'vibration',   v_vib);
        add_reading(r.asset_id, 'bearing_tmp', v_brg);
        add_reading(r.asset_id, 'power',       v_pow);
        add_reading(r.asset_id, 'flow',        v_flow);
        add_reading(r.asset_id, 'pressure',    v_pres);
        SELECT JSON_OBJECT('time' VALUE l_ts_txt,
                           'vibration'   VALUE ROUND(v_vib, 3),  'bearing_tmp' VALUE ROUND(v_brg, 3),
                           'power'       VALUE ROUND(v_pow, 3),  'flow'        VALUE ROUND(v_flow, 3),
                           'pressure'    VALUE ROUND(v_pres, 3))
        INTO   l_body FROM dual;
      ELSE
        v_tsup := 45 + (100 + 8 * l_load - 45) * l_s + 0.6 * DBMS_RANDOM.NORMAL;
        v_tret := 40 + (52 + 4 * l_load - 40) * l_s + 0.8 * DBMS_RANDOM.NORMAL;
        v_tsec := CASE WHEN r.asset_id = l_stuck THEN 41.0
                       ELSE 38 + (66 + 3 * l_load - 38) * l_s + 0.5 * DBMS_RANDOM.NORMAL END;
        v_dp   := 0.1 + (1.15 + 0.1 * l_load - 0.1) * l_s + 0.03 * DBMS_RANDOM.NORMAL;
        v_flow := r.rated_kw / 1000 * 30 * l_load * (0.1 + 0.9 * l_s) + 0.8 * DBMS_RANDOM.NORMAL;
        add_reading(r.asset_id, 't_supply', v_tsup);
        add_reading(r.asset_id, 't_return', v_tret);
        add_reading(r.asset_id, 't_sec',    v_tsec);
        add_reading(r.asset_id, 'dp',       v_dp);
        add_reading(r.asset_id, 'flow',     v_flow);
        SELECT JSON_OBJECT('time' VALUE l_ts_txt,
                           't_supply' VALUE ROUND(v_tsup, 3), 't_return' VALUE ROUND(v_tret, 3),
                           't_sec'    VALUE ROUND(v_tsec, 3), 'dp'       VALUE ROUND(v_dp, 3),
                           'flow'     VALUE ROUND(v_flow, 3))
        INTO   l_body FROM dual;
      END IF;
      l_bd(l_bd.COUNT + 1).asset_id := r.asset_id;
      l_bd(l_bd.COUNT).body         := l_body;
    END LOOP;

    UPDATE dh_sim_state SET pump_state = 'SPIKE_SENT' WHERE pump_state = 'SPIKE';

    -- 3. store
    IF l_store THEN
      FORALL i IN 1 .. l_n
        INSERT /*+ IGNORE_ROW_ON_DUPKEY_INDEX(dh_telemetry, dh_telemetry_pk) */
        INTO dh_telemetry (asset_id, metric, ts, value, source)
        VALUES (l_rd(i).asset_id, l_rd(i).metric, l_now, l_rd(i).value, 'SIMULATED');
    END IF;

    set_cfg('SIM_LAST_TICK', TO_CHAR(l_now, 'YYYY-MM-DD"T"HH24:MI:SS.FF3'));
    COMMIT;   -- the readings are safe before the HTTPS calls start

    -- 4. publish
    IF l_publish THEN
      IF NOT publish_ready(l_reason) THEN
        log_msg('PUBLISH', 'skipped: ' || l_reason);
      ELSE
        l_url := device_url;
        l_pwd := dh_secret.get_secret('IOT_DEVICE_PASSWORD');
        FOR i IN 1 .. l_bd.COUNT LOOP
          l_status := post_reading(l_bd(i).asset_id, l_bd(i).body, l_url, l_pwd, l_resp);
          IF l_status BETWEEN 200 AND 299 THEN
            l_ok := l_ok + 1;
            UPDATE dh_sim_state SET last_http_status = l_status, last_publish_at = l_now, last_error = NULL
            WHERE  asset_id = l_bd(i).asset_id;
          ELSE
            l_err := l_err + 1;
            l_last_err := l_bd(i).asset_id || ': HTTP ' || l_status || ' ' || l_resp;
            UPDATE dh_sim_state SET last_http_status = l_status, last_publish_at = l_now,
                                    last_error = SUBSTRB(l_resp, 1, 400)
            WHERE  asset_id = l_bd(i).asset_id;
          END IF;
        END LOOP;
        COMMIT;
        IF l_err > 0 THEN
          log_msg('PUBLISH', l_ok || ' sent, ' || l_err || ' failed; last: ' || l_last_err);
        END IF;
      END IF;
    END IF;
  END tick;

  -- ---------------------------------------------------------------------------
  PROCEDURE trip (p_asset_id IN VARCHAR2 DEFAULT 'PS-04') IS
  BEGIN
    ensure_state;
    UPDATE dh_sim_state SET pump_state = 'SPIKE'
    WHERE  asset_id = UPPER(p_asset_id) AND pump_state = 'RUNNING'
    AND    asset_id IN (SELECT asset_id FROM dh_assets WHERE asset_type = 'PUMP_STATION');
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20200, UPPER(p_asset_id) || ' is not a running pump station');
    END IF;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE(UPPER(p_asset_id) || ': vibration spike at the next tick, trips at the tick after (about 30-60 s)');
  END trip;

  PROCEDURE repair_asset (p_asset_id IN VARCHAR2) IS
  BEGIN
    UPDATE dh_sim_state SET pump_state = 'RUNNING', wear = 0 WHERE asset_id = p_asset_id;
    IF cfg('SIM_STUCK_SENSOR') = p_asset_id THEN
      set_cfg('SIM_STUCK_SENSOR', 'NONE');          -- sensor replaced: real values again
    END IF;
  END repair_asset;

  PROCEDURE repair (p_asset_id IN VARCHAR2 DEFAULT 'PS-04') IS
    l_asset   dh_assets.asset_id%TYPE := UPPER(TRIM(p_asset_id));
    l_faulty  PLS_INTEGER;
    l_wo_n    PLS_INTEGER;
    l_wo_list VARCHAR2(200);
  BEGIN
    -- was there anything to repair? (pump stopped or tripping, bearing wear, stuck sensor)
    SELECT COUNT(*) INTO l_faulty FROM dh_sim_state
    WHERE  asset_id = l_asset AND (pump_state <> 'RUNNING' OR wear > 0);
    IF cfg('SIM_STUCK_SENSOR') = l_asset THEN
      l_faulty := l_faulty + 1;
    END IF;

    repair_asset(l_asset);

    -- the open work orders of the asset are done
    SELECT COUNT(*), LISTAGG(wo_id, ', ' ON OVERFLOW TRUNCATE) WITHIN GROUP (ORDER BY wo_id)
    INTO   l_wo_n, l_wo_list
    FROM   dh_work_orders
    WHERE  asset_id = l_asset AND status IN ('NEW', 'PLANNED', 'IN_PROGRESS');
    UPDATE dh_work_orders SET status = 'DONE'
    WHERE  asset_id = l_asset AND status IN ('NEW', 'PLANNED', 'IN_PROGRESS');

    -- one entry in the maintenance history, only if something was done
    -- (a second call on a healthy asset without open work orders adds nothing)
    IF l_faulty > 0 OR l_wo_n > 0 THEN
      INSERT INTO dh_maintenance (maint_id, asset_id, performed_on, maint_type, description, downtime_hours)
      VALUES ('R-' || TO_CHAR(SYSTIMESTAMP, 'YYMMDDHH24MISSFF3'), l_asset, SYSDATE, 'CORRECTIVE',
              'Repaired and restarted'
              || CASE WHEN l_wo_n > 0 THEN '; work order' || CASE WHEN l_wo_n > 1 THEN 's' END
                                           || ' ' || l_wo_list || ' done' END,
              NULL);
    END IF;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE(l_asset || ': repaired and restarted'
                         || CASE WHEN l_wo_n > 0 THEN ', work orders done: ' || l_wo_list END);
  END repair;

  PROCEDURE reset IS
  BEGIN
    DELETE FROM dh_sim_state;
    UPDATE dh_config SET value = NULL WHERE name = 'SIM_LAST_TICK';
    set_cfg('SIM_STUCK_SENSOR', 'SS-09.3');
    COMMIT;
    ensure_state;
    COMMIT;
  END reset;

  -- ---------------------------------------------------------------------------
  FUNCTION status RETURN VARCHAR2 IS
    -- Separate queries: scalar subqueries next to aggregates raise ORA-00937
    l_pumps    VARCHAR2(1000);
    l_bypass   VARCHAR2(1000);
    l_cold     NUMBER;
    l_wear4    NUMBER;
    l_wear8    NUMBER;
    l_ok       NUMBER;
    l_failed   NUMBER;
    l_sent     NUMBER;
  BEGIN
    SELECT LISTAGG(CASE WHEN s.pump_state <> 'RUNNING' THEN s.asset_id || ' ' || s.pump_state END, ', ')
             WITHIN GROUP (ORDER BY s.asset_id),
           COUNT(CASE WHEN a.asset_type = 'SUBSTATION' AND s.supply < 0.5 THEN 1 END),
           MAX(CASE s.asset_id WHEN 'PS-04' THEN s.wear END),
           MAX(CASE s.asset_id WHEN 'PS-08' THEN s.wear END),
           COUNT(CASE WHEN s.last_http_status BETWEEN 200 AND 299 THEN 1 END),
           COUNT(CASE WHEN s.last_http_status NOT BETWEEN 200 AND 299 THEN 1 END),
           COUNT(s.last_http_status)
    INTO   l_pumps, l_cold, l_wear4, l_wear8, l_ok, l_failed, l_sent
    FROM   dh_sim_state s JOIN dh_assets a ON a.asset_id = s.asset_id;

    SELECT LISTAGG(pipe_id, ', ') WITHIN GROUP (ORDER BY pipe_id)
    INTO   l_bypass
    FROM   dh_pipes
    WHERE  pipe_kind = 'BYPASS' AND valve_state = 'OPEN';

    RETURN 'pumps not running: ' || NVL(l_pumps, '-')
        || ' | open bypass: ' || NVL(l_bypass, '-')
        || ' | substations without supply: ' || l_cold
        || ' | wear PS-04 ' || TO_CHAR(l_wear4, 'FM990.00') || ' PS-08 ' || TO_CHAR(l_wear8, 'FM990.00') || ' mm/s'
        || ' | last tick: ' || NVL(cfg('SIM_LAST_TICK'), '-') || ' UTC'
        || ' | publish: ' || CASE WHEN l_sent = 0 THEN 'off or not yet'
                                  ELSE l_ok || ' ok, ' || l_failed || ' failed' END;
  END status;

  -- ---------------------------------------------------------------------------
  PROCEDURE publish_test (p_asset_id IN VARCHAR2 DEFAULT 'PS-04') IS
    l_type   dh_assets.asset_type%TYPE;
    l_body   VARCHAR2(4000);
    l_reason VARCHAR2(200);
    l_resp   VARCHAR2(400);
    l_status NUMBER;
    l_ts_txt VARCHAR2(30) := TO_CHAR(utc_now, 'YYYY-MM-DD"T"HH24:MI:SS.FF6"Z"');
  BEGIN
    IF NOT publish_ready(l_reason) THEN
      RAISE_APPLICATION_ERROR(-20201, l_reason || ' in DH_CONFIG');
    END IF;
    SELECT asset_type INTO l_type FROM dh_assets WHERE asset_id = UPPER(p_asset_id);
    IF l_type = 'PUMP_STATION' THEN
      SELECT JSON_OBJECT('time' VALUE l_ts_txt, 'vibration' VALUE 2.1, 'bearing_tmp' VALUE 52.4,
                         'power' VALUE 251.0, 'flow' VALUE 930.0, 'pressure' VALUE 9.6)
      INTO l_body FROM dual;
    ELSE
      SELECT JSON_OBJECT('time' VALUE l_ts_txt, 't_supply' VALUE 104.0, 't_return' VALUE 54.0,
                         't_sec' VALUE 67.5, 'dp' VALUE 1.2, 'flow' VALUE 48.0)
      INTO l_body FROM dual;
    END IF;
    DBMS_OUTPUT.PUT_LINE('POST ' || device_url);
    DBMS_OUTPUT.PUT_LINE('body ' || l_body);
    l_status := post_reading(UPPER(p_asset_id), l_body, device_url, dh_secret.get_secret('IOT_DEVICE_PASSWORD'), l_resp);
    DBMS_OUTPUT.PUT_LINE('HTTP ' || l_status || ' ' || l_resp);
    DBMS_OUTPUT.PUT_LINE(CASE WHEN l_status BETWEEN 200 AND 299
                              THEN 'OK (accepted): check the tab Data of the twin in the OCI Console; if it stays {}, see REJECTED_DATA (scripts/README.md, step 7)'
                              ELSE 'Failed: see scripts/README.md, chapter "Setting up the OCI IoT Platform", step 7' END);
  END publish_test;

END dh_device_sim;
/
