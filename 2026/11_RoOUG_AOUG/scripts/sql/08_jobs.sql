-- =============================================================================
-- 08_jobs.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-10-28
--
-- One scheduler job, DH_TICK_JOB, every 30 seconds:
--   1. device simulation: readings for 50 twins, stored and/or posted to the
--      OCI IoT Platform (DH_DEVICE_SIM, 06b_device_sim.sql)  - if SIM_ENABLED = Y
--   2. pull historized data from the IoT Data API (DH_IOT_SYNC) - only if INGEST_MODE = IOT
--   3. detect anomalies and update health status (DH_ANALYTICS)
-- Each step has its own error handler, so a failing step does not stop the
-- others. Errors go to DH_JOB_LOG.
--
-- DH_CONFIG 'INGEST_MODE' = DIRECT  database simulation -> DH_TELEMETRY (default)
--                         = IOT     database simulation -> IoT Platform -> pull
--                                   (needs an identity domain application, see
--                                   scripts/README.md, optional steps)
--
-- Idempotent: settings are only added if missing, the job is only created once.
-- Migration from the first version: INGEST_MODE 'IOT' without OAuth client is
-- switched to 'DIRECT' (the pull could never work without it).
-- =============================================================================

MERGE INTO dh_config c USING (SELECT 'INGEST_MODE' name, 'DIRECT' value FROM dual) s
ON (c.name = s.name) WHEN NOT MATCHED THEN INSERT (name, value) VALUES (s.name, s.value);
UPDATE dh_config SET value = 'DIRECT'
WHERE  name = 'INGEST_MODE' AND value = 'IOT'
AND    (SELECT value FROM dh_config WHERE name = 'IOT_CLIENT_ID') IS NULL;
COMMIT;

CREATE OR REPLACE PROCEDURE dh_job_tick IS
  FUNCTION cfg (p_name IN VARCHAR2, p_default IN VARCHAR2) RETURN VARCHAR2 IS
    l_value dh_config.value%TYPE;
  BEGIN
    SELECT NVL(MAX(value), p_default) INTO l_value FROM dh_config WHERE name = p_name;
    RETURN l_value;
  END cfg;
BEGIN
  IF cfg('SIM_ENABLED', 'Y') = 'Y' THEN
    BEGIN
      dh_device_sim.tick;
    EXCEPTION WHEN OTHERS THEN
      ROLLBACK;
      dh_device_sim.log_msg('SIMULATION', SQLERRM);
    END;
  END IF;

  IF cfg('INGEST_MODE', 'DIRECT') = 'IOT' THEN
    BEGIN
      dh_iot_sync.pull;
    EXCEPTION WHEN OTHERS THEN
      ROLLBACK;
      dh_device_sim.log_msg('IOT_PULL', SQLERRM);
    END;
  END IF;

  BEGIN
    dh_analytics.run;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    dh_device_sim.log_msg('ANALYTICS', SQLERRM);
  END;
END dh_job_tick;
/

-- Create the job only if it does not exist; on re-run update action, interval
-- and comment but keep its enabled/disabled state.
DECLARE
  l_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_n FROM user_scheduler_jobs WHERE job_name = 'DH_TICK_JOB';
  IF l_n = 0 THEN
    DBMS_SCHEDULER.CREATE_JOB(
      job_name        => 'DH_TICK_JOB',
      job_type        => 'STORED_PROCEDURE',
      job_action      => 'DH_JOB_TICK',
      repeat_interval => 'FREQ=SECONDLY;INTERVAL=30',
      enabled         => FALSE,
      comments        => 'District heating demo: device simulation, IoT publish, anomaly detection');
  ELSE
    DBMS_SCHEDULER.SET_ATTRIBUTE('DH_TICK_JOB', 'job_action',      'DH_JOB_TICK');
    DBMS_SCHEDULER.SET_ATTRIBUTE('DH_TICK_JOB', 'repeat_interval', 'FREQ=SECONDLY;INTERVAL=30');
    DBMS_SCHEDULER.SET_ATTRIBUTE('DH_TICK_JOB', 'comments',
                                 'District heating demo: device simulation, IoT publish, anomaly detection');
  END IF;
END;
/

-- Start before the session:  EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB');
-- Stop after the session:    EXEC DBMS_SCHEDULER.DISABLE('DH_TICK_JOB', force => TRUE);
-- One step by hand:          EXEC dh_job_tick
-- Check the job:   SELECT log_date, status, additional_info FROM user_scheduler_job_run_details
--                  WHERE job_name = 'DH_TICK_JOB' ORDER BY log_date DESC FETCH FIRST 10 ROWS ONLY;
-- Check the steps: SELECT logged_at, step, message FROM dh_job_log ORDER BY log_id DESC FETCH FIRST 20 ROWS ONLY;
-- Simulation:      SELECT dh_device_sim.status FROM dual;
