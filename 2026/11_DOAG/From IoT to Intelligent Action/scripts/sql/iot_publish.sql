-- =============================================================================
-- iot_publish.sql - switches the posts to the OCI IoT Platform on or off
--
-- Author:      Karin Patenge
-- Last update: 2026-11-13
--
-- Run as the demo user (GRAPHAI) from the scripts folder in SQLcl:
--   @sql/iot_publish.sql off     -- stop the feeds into the digital twins
--   @sql/iot_publish.sql on      -- start them again
--   @sql/iot_publish.sql         -- only show the current settings
--
-- The device simulation (06b_device_sim.sql) posts every reading to the twins
-- when IOT_PUBLISH = Y or INGEST_MODE = IOT. "off" therefore sets IOT_PUBLISH = N
-- and INGEST_MODE = DIRECT: DH_TICK_JOB keeps running and writes into
-- DH_TELEMETRY, so APEX, the graph and the agent are not affected; only the
-- twins stop updating. "on" sets IOT_PUBLISH = Y; it needs the device host and
-- the device password (asked by 00c_install_all.sql or 01_schema.sql).
-- The change takes effect at the next tick (every 30 seconds). The job itself
-- is not changed: stop_tick_job.sql stops everything.
-- Safe to run again.
-- =============================================================================
SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK OFF
SET SERVEROUTPUT ON

-- Optional argument: define 1 as empty if it was not given
COLUMN 1 NEW_VALUE 1 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
COLUMN 1 CLEAR

DECLARE
  l_arg  VARCHAR2(20) := LOWER(TRIM('&1'));
  l_host dh_config.value%TYPE;
  l_pwd  PLS_INTEGER;

  PROCEDURE set_cfg (p_name IN VARCHAR2, p_value IN VARCHAR2) IS
  BEGIN
    MERGE INTO dh_config c USING (SELECT p_name AS name, p_value AS value FROM dual) s
    ON (c.name = s.name)
    WHEN MATCHED THEN UPDATE SET c.value = s.value
    WHEN NOT MATCHED THEN INSERT (name, value) VALUES (s.name, s.value);
  END set_cfg;
BEGIN
  IF l_arg = 'off' THEN
    set_cfg('IOT_PUBLISH', 'N');
    set_cfg('INGEST_MODE', 'DIRECT');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Posts to the IoT Platform: OFF from the next tick. The simulation keeps running.');
  ELSIF l_arg = 'on' THEN
    SELECT MAX(CASE name WHEN 'IOT_DEVICE_HOST' THEN value END),
           COUNT(CASE WHEN name = 'IOT_DEVICE_PASSWORD' AND secret_value IS NOT NULL THEN 1 END)
    INTO   l_host, l_pwd
    FROM   dh_config;
    IF l_host IS NULL OR l_pwd = 0 THEN
      RAISE_APPLICATION_ERROR(-20301,
        'Device host or device password missing: run @sql/01_schema.sql and answer the IoT questions');
    END IF;
    set_cfg('IOT_PUBLISH', 'Y');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Posts to the IoT Platform: ON from the next tick (device host ' || l_host || ').');
  ELSIF l_arg IS NOT NULL THEN
    RAISE_APPLICATION_ERROR(-20300, 'Argument: on, off, or none to show the settings');
  END IF;
END;
/

PROMPT
COLUMN name  FORMAT A20
COLUMN value FORMAT A70
SELECT name, value
FROM   dh_config
WHERE  name IN ('IOT_PUBLISH', 'INGEST_MODE', 'IOT_DEVICE_HOST', 'IOT_DEVICE_PASSWORD')
ORDER  BY name;

COLUMN job_enabled FORMAT A12
SELECT enabled AS job_enabled FROM user_scheduler_jobs WHERE job_name = 'DH_TICK_JOB';
PROMPT Posts only happen while DH_TICK_JOB is enabled (EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')).
COLUMN name CLEAR
COLUMN value CLEAR
COLUMN job_enabled CLEAR
SET FEEDBACK ON
