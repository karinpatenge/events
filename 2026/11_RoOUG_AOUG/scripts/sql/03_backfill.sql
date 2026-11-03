-- =============================================================================
-- 03_backfill.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-10-27
--
-- Package DH_SIM: generates 7 days of telemetry history in the database, so the
-- demo starts with trends (PS-04 bearing wear over 3 days, PS-08 slow wear,
-- SS-09.3 stuck sensor in the last hour). The live part comes from the
-- database device simulation DH_DEVICE_SIM (06b_device_sim.sql), which starts
-- where this history ends.
--
-- The same formulas are used by 06b_device_sim.sql. Keep them in sync.
-- All timestamps are UTC.
--
--   EXEC dh_sim.backfill;            -- 7 days up to now (run right before the session)
--   EXEC dh_sim.backfill(p_days => 3, p_step_min => 5);
-- =============================================================================

CREATE OR REPLACE PACKAGE dh_sim AS
  -- Deletes BACKFILL rows, generates history up to p_end (UTC now by default).
  PROCEDURE backfill (p_days     IN NUMBER    DEFAULT 7,
                      p_step_min IN NUMBER    DEFAULT 5,
                      p_end      IN TIMESTAMP DEFAULT NULL);
  -- Resets anomalies, work orders, health, bypass valves, live telemetry and the
  -- state of the device simulation (keeps topology and the backfill history).
  PROCEDURE reset_state;
  -- UTC now as TIMESTAMP(3)
  FUNCTION utc_now RETURN TIMESTAMP;
END dh_sim;
/

CREATE OR REPLACE PACKAGE BODY dh_sim AS

  FUNCTION utc_now RETURN TIMESTAMP IS
    l_ts TIMESTAMP(3);
  BEGIN
    SELECT CAST(SYS_EXTRACT_UTC(SYSTIMESTAMP) AS TIMESTAMP(3)) INTO l_ts FROM dual;   -- in SQL, not in PL/SQL
    RETURN l_ts;
  END utc_now;

  PROCEDURE reset_state IS
  BEGIN
    UPDATE dh_work_orders SET anomaly_id = NULL;
    DELETE FROM dh_work_orders WHERE created_by <> 'SEED';
    DELETE FROM dh_anomalies;
    DELETE FROM dh_telemetry WHERE source <> 'BACKFILL';   -- live data of earlier rehearsals
    UPDATE dh_assets SET health_status = 'OK', health_reason = NULL, health_updated = NULL, in_service = 'Y';
    UPDATE dh_pipes  SET valve_state = 'CLOSED' WHERE pipe_kind = 'BYPASS';
    DELETE FROM dh_sim_state;                               -- recreated by the next tick
    UPDATE dh_config SET value = NULL WHERE name IN ('SIM_LAST_TICK', 'IOT_LAST_TS');
    COMMIT;
  END reset_state;

  PROCEDURE backfill (p_days IN NUMBER DEFAULT 7, p_step_min IN NUMBER DEFAULT 5, p_end IN TIMESTAMP DEFAULT NULL) IS
    l_end   TIMESTAMP(3) := NVL(p_end, utc_now);
    l_steps PLS_INTEGER  := TRUNC(p_days * 24 * 60 / p_step_min);
  BEGIN
    DELETE FROM dh_telemetry WHERE source = 'BACKFILL';
    DBMS_RANDOM.SEED(2026);

    -- PL/SQL does not accept INSERT ... WITH directly: the WITH sits in an inline view
    INSERT INTO dh_telemetry (asset_id, metric, ts, value, source)
    SELECT * FROM (
    WITH steps AS (
      SELECT LEVEL - 1 AS n FROM dual CONNECT BY LEVEL <= l_steps
    ), t AS (
      SELECT n,
             l_end - NUMTODSINTERVAL(n * p_step_min, 'MINUTE')                                AS ts,
             n * p_step_min / 60                                                              AS h_before,
             -- hour of day (UTC+1 local), drives the daily load profile
             MOD(EXTRACT(HOUR FROM (l_end - NUMTODSINTERVAL(n * p_step_min, 'MINUTE'))) + 1
                 + EXTRACT(MINUTE FROM (l_end - NUMTODSINTERVAL(n * p_step_min, 'MINUTE'))) / 60, 24) AS hod
      FROM steps
    ), l AS (
      SELECT t.*,
             0.80 + 0.12 * COS(2 * ACOS(-1) * (hod - 7) / 24) + 0.05 * COS(2 * ACOS(-1) * (hod - 19) / 12) AS load,
             -- PS-04: bearing wear over the last 72 h (accelerating)
             POWER(GREATEST(0, (72 - h_before) / 72), 1.8)                                    AS wear4,
             -- PS-08: slow wear over the last 120 h (linear)
             GREATEST(0, (120 - h_before) / 120)                                              AS wear8
      FROM t
    )
    SELECT a.asset_id, m.metric, l.ts,
           ROUND(CASE
             WHEN m.metric = 'vibration'   THEN 2.0 + 0.1 * l.load + 0.12 * DBMS_RANDOM.NORMAL
                                                + CASE a.asset_id WHEN 'PS-04' THEN 4.4 * l.wear4 WHEN 'PS-08' THEN 2.2 * l.wear8 ELSE 0 END
             WHEN m.metric = 'bearing_tmp' THEN 46 + 8 * l.load + 0.6 * DBMS_RANDOM.NORMAL
                                                + CASE a.asset_id WHEN 'PS-04' THEN 26 * l.wear4 WHEN 'PS-08' THEN 9 * l.wear8 ELSE 0 END
             WHEN m.metric = 'power'       THEN a.rated_kw * (0.55 + 0.35 * l.load) * (1 + 0.01 * DBMS_RANDOM.NORMAL)
                                                * CASE a.asset_id WHEN 'PS-04' THEN 1 + 0.05 * l.wear4 ELSE 1 END
             WHEN m.metric = 'flow' AND a.asset_type = 'PUMP_STATION'
                                           THEN 1000 * l.load + 15 * DBMS_RANDOM.NORMAL
             WHEN m.metric = 'pressure'    THEN 9.3 + 0.4 * l.load + 0.05 * DBMS_RANDOM.NORMAL
             WHEN m.metric = 't_supply'    THEN 100 + 8 * l.load + 0.6 * DBMS_RANDOM.NORMAL
             WHEN m.metric = 't_return'    THEN 52 + 4 * l.load + 0.8 * DBMS_RANDOM.NORMAL
             WHEN m.metric = 't_sec'       THEN CASE WHEN a.asset_id = 'SS-09.3' AND l.h_before < 1 THEN 41.0
                                                     ELSE 66 + 3 * l.load + 0.5 * DBMS_RANDOM.NORMAL END
             WHEN m.metric = 'dp'          THEN 1.15 + 0.1 * l.load + 0.03 * DBMS_RANDOM.NORMAL
             WHEN m.metric = 'flow'        THEN a.rated_kw / 1000 * 30 * l.load + 0.8 * DBMS_RANDOM.NORMAL
           END, 3) AS value,
           'BACKFILL'
    FROM   dh_assets  a
    JOIN   dh_metrics m ON m.asset_type = a.asset_type
    CROSS  JOIN l
    WHERE  a.asset_type IN ('PUMP_STATION', 'SUBSTATION')
    );

    COMMIT;

    -- Optimizer statistics: helpful, not required (Autonomous Database also
    -- gathers them automatically). A fixed 100 % sample is used on purpose:
    -- the default AUTO_SAMPLE_SIZE path failed in the demo database with
    -- ORA-04063 on SYS.DBMS_SQLTUNE_INTERNAL; ~500,000 rows take seconds.
    -- A failure here must not fail the backfill.
    BEGIN
      DBMS_STATS.GATHER_TABLE_STATS(ownname => USER, tabname => 'DH_TELEMETRY', estimate_percent => 100);
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Note: statistics not gathered (' || SQLERRM || '); data is complete.');
    END;
  END backfill;

END dh_sim;
/
