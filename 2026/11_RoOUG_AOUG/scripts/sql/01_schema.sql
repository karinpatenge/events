-- =============================================================================
-- 01_schema.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-11-04
--
-- Relational foundation for the district heating demo (schema OGBEMEA2026).
--
--   dh_assets       plants, pump stations, substations, buildings (vertices)
--   dh_pipes        pipes and valves between assets (edges, flow direction)
--   dh_metrics      telemetry metrics per asset type with limits
--   dh_telemetry    time series: 7-day history, live readings of the database
--                   device simulation, or pulled from the OCI IoT Platform
--   dh_anomalies    findings of the detection job (vertices + edges to assets)
--   dh_work_orders  work orders, also created by the agent
--   dh_maintenance  maintenance history (context for the agent)
--   dh_config       key/value settings (city, simulation, IoT Platform, ...);
--                   passwords encrypted (package DH_SECRET)
--   dh_sim_state    state of the simulated devices (06b_device_sim.sql)
--   dh_job_log      messages of the scheduler job (one day)
--
-- Asks for the device settings of the IoT Platform (end of the script): domain
-- short ID (-> device host), device password (hidden), publish Y/N.
-- Press Enter to keep the current value.
--
-- Idempotent: tables and indexes are created only if missing (IF NOT EXISTS,
-- Oracle AI Database 23ai/26ai); reference data is merged; existing settings
-- in DH_CONFIG are kept unless you enter a new ID.
-- Note: IF NOT EXISTS does not change an existing table. After a change of a
-- table definition, run 99_teardown.sql first (or ALTER TABLE by hand).
-- =============================================================================

CREATE TABLE IF NOT EXISTS dh_config (
  name          VARCHAR2(64)  PRIMARY KEY,
  value         VARCHAR2(4000),
  secret_value  RAW(2000)                -- encrypted secrets, see DH_SECRET below
);

CREATE TABLE IF NOT EXISTS dh_assets (
  asset_id        VARCHAR2(20)  PRIMARY KEY,
  asset_type      VARCHAR2(20)  NOT NULL
                  CONSTRAINT dh_assets_type_ck CHECK (asset_type IN ('PLANT','PUMP_STATION','SUBSTATION','BUILDING')),
  name            VARCHAR2(100) NOT NULL,
  district        VARCHAR2(50),
  latitude        NUMBER(9,6),
  longitude       NUMBER(9,6),
  install_year    NUMBER(4),
  equipment       VARCHAR2(100),
  rated_kw        NUMBER,
  apartments      NUMBER,
  building_type   VARCHAR2(20),
  criticality     NUMBER(1)     DEFAULT 1 NOT NULL,      -- 1 low .. 5 life-critical
  in_service      CHAR(1)       DEFAULT 'Y' NOT NULL CONSTRAINT dh_assets_svc_ck CHECK (in_service IN ('Y','N')),
  health_status   VARCHAR2(10)  DEFAULT 'OK' NOT NULL
                  CONSTRAINT dh_assets_health_ck CHECK (health_status IN ('OK','WATCH','WARNING','ALARM')),
  health_reason   VARCHAR2(400),
  health_updated  TIMESTAMP,
  twin_ocid       VARCHAR2(255),                         -- OCI IoT digital twin instance
  CONSTRAINT dh_assets_twin_uk UNIQUE (twin_ocid)
);

CREATE TABLE IF NOT EXISTS dh_pipes (
  pipe_id       VARCHAR2(20)  PRIMARY KEY,
  from_asset    VARCHAR2(20)  NOT NULL CONSTRAINT dh_pipes_from_fk REFERENCES dh_assets,
  to_asset      VARCHAR2(20)  NOT NULL CONSTRAINT dh_pipes_to_fk   REFERENCES dh_assets,
  pipe_kind     VARCHAR2(20)  NOT NULL
                CONSTRAINT dh_pipes_kind_ck CHECK (pipe_kind IN ('MAIN','BYPASS','DISTRIBUTION','SERVICE')),
  diameter_mm   NUMBER,
  length_m      NUMBER,
  material      VARCHAR2(50),
  install_year  NUMBER(4),
  valve_state   VARCHAR2(10)  DEFAULT 'OPEN' NOT NULL
                CONSTRAINT dh_pipes_valve_ck CHECK (valve_state IN ('OPEN','CLOSED'))
);
CREATE INDEX IF NOT EXISTS dh_pipes_from_ix ON dh_pipes (from_asset);
CREATE INDEX IF NOT EXISTS dh_pipes_to_ix   ON dh_pipes (to_asset);

CREATE TABLE IF NOT EXISTS dh_metrics (
  asset_type    VARCHAR2(20) NOT NULL,
  metric        VARCHAR2(30) NOT NULL,      -- = DTDL telemetry name = IoT content path
  display_name  VARCHAR2(60) NOT NULL,
  unit          VARCHAR2(20),
  normal_value  NUMBER,
  warn_low      NUMBER,
  warn_high     NUMBER,
  alarm_low     NUMBER,
  alarm_high    NUMBER,
  predict       CHAR(1) DEFAULT 'N' NOT NULL,   -- trend-based prediction (time to alarm)
  CONSTRAINT dh_metrics_pk PRIMARY KEY (asset_type, metric)
);

CREATE TABLE IF NOT EXISTS dh_telemetry (
  asset_id  VARCHAR2(20) NOT NULL CONSTRAINT dh_tel_asset_fk REFERENCES dh_assets,
  metric    VARCHAR2(30) NOT NULL,
  ts        TIMESTAMP(3) NOT NULL,
  value     NUMBER       NOT NULL,
  source    VARCHAR2(10) DEFAULT 'IOT' NOT NULL,   -- BACKFILL | SIMULATED | IOT | DIRECT
  CONSTRAINT dh_telemetry_pk PRIMARY KEY (asset_id, metric, ts)
);
CREATE INDEX IF NOT EXISTS dh_telemetry_ts_ix ON dh_telemetry (ts);

CREATE TABLE IF NOT EXISTS dh_anomalies (
  anomaly_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  asset_id        VARCHAR2(20)  NOT NULL CONSTRAINT dh_anom_asset_fk REFERENCES dh_assets,
  metric          VARCHAR2(30)  NOT NULL,
  anomaly_type    VARCHAR2(12)  NOT NULL
                  CONSTRAINT dh_anom_type_ck CHECK (anomaly_type IN ('THRESHOLD','ZSCORE','TREND','FLATLINE','NO_DATA')),
  severity        VARCHAR2(10)  NOT NULL
                  CONSTRAINT dh_anom_sev_ck CHECK (severity IN ('WATCH','WARNING','ALARM')),
  status          VARCHAR2(10)  DEFAULT 'OPEN' NOT NULL
                  CONSTRAINT dh_anom_status_ck CHECK (status IN ('OPEN','ACK','CLOSED')),
  detected_at     TIMESTAMP     NOT NULL,
  last_seen_at    TIMESTAMP     NOT NULL,
  observed_value  NUMBER,
  expected_value  NUMBER,
  score           NUMBER,                       -- z-score or slope
  hours_to_alarm  NUMBER,                       -- TREND only
  details         VARCHAR2(400)
);
CREATE INDEX IF NOT EXISTS dh_anom_asset_ix ON dh_anomalies (asset_id, status);

CREATE TABLE IF NOT EXISTS dh_work_orders (
  wo_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  asset_id     VARCHAR2(20)  NOT NULL CONSTRAINT dh_wo_asset_fk REFERENCES dh_assets,
  anomaly_id   NUMBER        CONSTRAINT dh_wo_anom_fk REFERENCES dh_anomalies,
  created_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  priority     VARCHAR2(2)   NOT NULL CONSTRAINT dh_wo_prio_ck CHECK (priority IN ('P1','P2','P3','P4')),
  title        VARCHAR2(200) NOT NULL,
  details      CLOB,
  status       VARCHAR2(12)  DEFAULT 'NEW' NOT NULL
               CONSTRAINT dh_wo_status_ck CHECK (status IN ('NEW','PLANNED','IN_PROGRESS','DONE','CANCELLED')),
  created_by   VARCHAR2(60)  DEFAULT 'OPERATOR' NOT NULL
);
CREATE INDEX IF NOT EXISTS dh_wo_asset_ix ON dh_work_orders (asset_id);

-- Work order status IN_PROGRESS (NEW -> PLANNED -> IN_PROGRESS -> DONE, moved by
-- the APEX workflow "Work Order", 10_work_orders.sql). For a table created by an earlier version: widen the
-- column and renew the check constraint. Safe to re-run.
DECLARE
  l_len NUMBER;
  l_ok  NUMBER;
BEGIN
  SELECT data_length INTO l_len FROM user_tab_columns
  WHERE  table_name = 'DH_WORK_ORDERS' AND column_name = 'STATUS';
  IF l_len < 12 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE dh_work_orders MODIFY (status VARCHAR2(12))';
  END IF;
  SELECT COUNT(*) INTO l_ok FROM user_constraints
  WHERE  table_name = 'DH_WORK_ORDERS' AND constraint_name = 'DH_WO_STATUS_CK'
  AND    search_condition_vc LIKE '%IN_PROGRESS%';
  IF l_ok = 0 THEN
    BEGIN
      EXECUTE IMMEDIATE 'ALTER TABLE dh_work_orders DROP CONSTRAINT dh_wo_status_ck';
    EXCEPTION WHEN OTHERS THEN
      IF SQLCODE <> -2443 THEN RAISE; END IF;      -- constraint does not exist
    END;
    EXECUTE IMMEDIATE q'[ALTER TABLE dh_work_orders ADD CONSTRAINT dh_wo_status_ck
                         CHECK (status IN ('NEW','PLANNED','IN_PROGRESS','DONE','CANCELLED'))]';
  END IF;
END;
/

CREATE TABLE IF NOT EXISTS dh_maintenance (
  maint_id        VARCHAR2(20)  PRIMARY KEY,
  asset_id        VARCHAR2(20)  NOT NULL CONSTRAINT dh_maint_asset_fk REFERENCES dh_assets,
  performed_on    DATE          NOT NULL,
  maint_type      VARCHAR2(20)  NOT NULL,
  description     VARCHAR2(400),
  downtime_hours  NUMBER
);
CREATE INDEX IF NOT EXISTS dh_maint_asset_ix ON dh_maintenance (asset_id);

-- Simulated devices: one row per pump station and substation
--   pump_state  RUNNING | SPIKE (trip requested) | SPIKE_SENT | STOPPED
--   wear        extra vibration in mm/s (bearing wear of PS-04 and PS-08)
--   supply      1 = fully supplied with heat .. 0 = no supply
CREATE TABLE IF NOT EXISTS dh_sim_state (
  asset_id          VARCHAR2(20)  NOT NULL,
  pump_state        VARCHAR2(12)  DEFAULT 'RUNNING' NOT NULL
                    CONSTRAINT dh_sim_state_ck CHECK (pump_state IN ('RUNNING','SPIKE','SPIKE_SENT','STOPPED')),
  wear              NUMBER        DEFAULT 0 NOT NULL,
  supply            NUMBER        DEFAULT 1 NOT NULL,
  last_http_status  NUMBER,                        -- last POST to the IoT Platform
  last_publish_at   TIMESTAMP(3),
  last_error        VARCHAR2(400),
  CONSTRAINT dh_sim_state_pk PRIMARY KEY (asset_id),
  CONSTRAINT dh_sim_asset_fk FOREIGN KEY (asset_id) REFERENCES dh_assets
);

CREATE TABLE IF NOT EXISTS dh_job_log (
  log_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  logged_at  TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  step       VARCHAR2(30)   NOT NULL,
  message    VARCHAR2(4000)
);

-- ---------------------------------------------------------------------------
-- Reference data: metrics and limits (illustrative values)
-- Vibration limits follow the spirit of ISO 10816-3 zones (mm/s RMS).
-- ---------------------------------------------------------------------------
MERGE INTO dh_metrics t
USING (VALUES
  ('PUMP_STATION','vibration',  'Vibration velocity',      'mm/s',  2.0,  NULL, 4.5,  NULL, 7.1,  'Y'),
  ('PUMP_STATION','bearing_tmp','Bearing temperature',     '°C',   52,    NULL, 75,   NULL, 90,   'Y'),
  ('PUMP_STATION','power',      'Motor power',             'kW',   NULL,  NULL, NULL, NULL, NULL, 'N'),
  ('PUMP_STATION','flow',       'Flow',                    'm³/h', 900,   500,  NULL, 250,  NULL, 'N'),
  ('PUMP_STATION','pressure',   'Discharge pressure',      'bar',  9.5,   8.0,  11.5, 6.5,  12.5, 'N'),
  ('SUBSTATION',  't_supply',   'Primary supply temp.',    '°C',   105,   85,   NULL, 75,   NULL, 'N'),
  ('SUBSTATION',  't_return',   'Primary return temp.',    '°C',   55,    NULL, 65,   NULL, 70,   'N'),
  ('SUBSTATION',  't_sec',      'Secondary supply temp.',  '°C',   68,    55,   NULL, 50,   NULL, 'N'),
  ('SUBSTATION',  'dp',         'Differential pressure',   'bar',  1.2,   0.6,  NULL, 0.3,  NULL, 'N'),
  ('SUBSTATION',  'flow',       'Flow',                    'm³/h', 60,    NULL, NULL, NULL, NULL, 'N')
) s (asset_type, metric, display_name, unit, normal_value, warn_low, warn_high, alarm_low, alarm_high, predict)
ON (t.asset_type = s.asset_type AND t.metric = s.metric)
WHEN MATCHED THEN UPDATE SET
  t.display_name = s.display_name, t.unit = s.unit, t.normal_value = s.normal_value,
  t.warn_low = s.warn_low, t.warn_high = s.warn_high, t.alarm_low = s.alarm_low,
  t.alarm_high = s.alarm_high, t.predict = s.predict
WHEN NOT MATCHED THEN INSERT (asset_type, metric, display_name, unit, normal_value, warn_low, warn_high,
                              alarm_low, alarm_high, predict)
  VALUES (s.asset_type, s.metric, s.display_name, s.unit, s.normal_value, s.warn_low, s.warn_high,
          s.alarm_low, s.alarm_high, s.predict);

-- Settings: inserted only if missing, existing values are kept
--   INGEST_MODE          DIRECT: the device simulation writes into DH_TELEMETRY (default)
--                        IOT:    the simulation only publishes, DH_IOT_SYNC pulls the
--                                historized data back (optional, see below)
--   SIM_ENABLED          Y: the job runs the database device simulation (06b_device_sim.sql)
--   SIM_LAST_TICK        time of the last simulation step (UTC)
--   IOT_PUBLISH          Y: the simulation also posts every reading to the IoT Platform
--   IOT_DEVICE_ENDPOINT  endpoint of the adapters (scripts/iot/adapter_*.json)
--   IOT_DEVICE_HOST      device host of the IoT domain, built from the domain short ID (below)
--   IOT_DEVICE_PASSWORD  device password = content of the Vault secret used by the twins,
--                        asked hidden below and stored encrypted (VALUE shows '********').
-- The settings of the optional pull through the IoT Data API (IOT_CLIENT_ID,
-- IOT_USER, IOT_TOKEN_URL, ...) are not created here. scripts/README.md,
-- optional chapter, step C, creates them only if you use that path.
MERGE INTO dh_config t
USING (VALUES
  ('CITY', 'VIE'),
  ('INGEST_MODE', 'DIRECT'),
  ('SIM_ENABLED', 'Y'),
  ('SIM_LAST_TICK', NULL),
  ('IOT_PUBLISH', 'N'),
  ('IOT_DEVICE_ENDPOINT', '/dh/telemetry'),
  ('IOT_DEVICE_PASSWORD', NULL)
) s (name, value)
ON (t.name = s.name)
WHEN NOT MATCHED THEN INSERT (name, value) VALUES (s.name, s.value);

-- Clean-up of earlier versions: empty or placeholder settings of the optional
-- pull are removed. Values you have filled in are kept.
DELETE FROM dh_config
WHERE  name IN ('IOT_DATA_API_BASE', 'IOT_TOKEN_URL', 'IOT_SCOPE', 'IOT_CLIENT_ID', 'IOT_CLIENT_SECRET',
                'IOT_USER', 'IOT_PASSWORD', 'IOT_LAST_TS', 'IOT_PAGE_SIZE')
AND    (value IS NULL OR value LIKE '%<%' OR (name = 'IOT_PAGE_SIZE' AND value = '500'));
COMMIT;

-- ---------------------------------------------------------------------------
-- Secrets (passwords) are stored encrypted. DH_CONFIG.VALUE then only shows
-- '********'; the encrypted value sits in DH_CONFIG.SECRET_VALUE (AES-256,
-- DBMS_CRYPTO). This keeps the password out of query results and screen
-- shares. It is masking, not real protection: the key is derived inside the
-- package, so the schema owner can decrypt. Production: use OCI Vault.
-- ---------------------------------------------------------------------------
DECLARE
  l_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_n FROM user_tab_columns WHERE table_name = 'DH_CONFIG' AND column_name = 'SECRET_VALUE';
  IF l_n = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE dh_config ADD (secret_value RAW(2000))';
  END IF;
END;
/

CREATE OR REPLACE PACKAGE dh_secret AS
  c_mask CONSTANT VARCHAR2(8) := '********';
  -- Stores p_plain encrypted under setting p_name; NULL removes the secret
  PROCEDURE set_secret (p_name IN VARCHAR2, p_plain IN VARCHAR2);
  -- Returns the decrypted secret, NULL if not set
  FUNCTION  get_secret (p_name IN VARCHAR2) RETURN VARCHAR2;
END dh_secret;
/

CREATE OR REPLACE PACKAGE BODY dh_secret AS
  c_typ CONSTANT PLS_INTEGER := DBMS_CRYPTO.ENCRYPT_AES256 + DBMS_CRYPTO.CHAIN_CBC + DBMS_CRYPTO.PAD_PKCS5;

  -- 256-bit key, derived from the database and the schema (nothing stored)
  FUNCTION derive_key RETURN RAW IS
  BEGIN
    RETURN DBMS_CRYPTO.HASH(UTL_I18N.STRING_TO_RAW(
             SYS_CONTEXT('USERENV', 'DB_UNIQUE_NAME') || ':' || USER || ':dh-demo-secret', 'AL32UTF8'),
             DBMS_CRYPTO.HASH_SH256);
  END derive_key;

  PROCEDURE set_secret (p_name IN VARCHAR2, p_plain IN VARCHAR2) IS
    l_iv  RAW(16);
    l_enc RAW(2000);
  BEGIN
    IF p_plain IS NOT NULL THEN
      l_iv  := DBMS_CRYPTO.RANDOMBYTES(16);
      l_enc := UTL_RAW.CONCAT(l_iv, DBMS_CRYPTO.ENCRYPT(
                 src => UTL_I18N.STRING_TO_RAW(p_plain, 'AL32UTF8'), typ => c_typ, key => derive_key, iv => l_iv));
    END IF;
    MERGE INTO dh_config c
    USING (SELECT p_name AS name FROM dual) s
    ON (c.name = s.name)
    WHEN MATCHED THEN UPDATE SET c.value = CASE WHEN l_enc IS NOT NULL THEN c_mask END, c.secret_value = l_enc
    WHEN NOT MATCHED THEN INSERT (name, value, secret_value)
      VALUES (s.name, CASE WHEN l_enc IS NOT NULL THEN c_mask END, l_enc);
  END set_secret;

  FUNCTION get_secret (p_name IN VARCHAR2) RETURN VARCHAR2 IS
    l_enc   RAW(2000);
    l_value dh_config.value%TYPE;
  BEGIN
    SELECT MAX(secret_value), MAX(value) INTO l_enc, l_value FROM dh_config WHERE name = p_name;
    IF l_enc IS NULL THEN
      -- not encrypted (yet): plain value, unless it is only the mask
      RETURN CASE WHEN l_value = c_mask THEN NULL ELSE l_value END;
    END IF;
    RETURN UTL_I18N.RAW_TO_CHAR(DBMS_CRYPTO.DECRYPT(
             src => UTL_RAW.SUBSTR(l_enc, 17), typ => c_typ, key => derive_key, iv => UTL_RAW.SUBSTR(l_enc, 1, 16)),
             'AL32UTF8');
  END get_secret;
END dh_secret;
/

-- Migration: secrets stored as plain text by earlier versions are encrypted now
BEGIN
  FOR r IN (SELECT name, value FROM dh_config
            WHERE  name IN ('IOT_DEVICE_PASSWORD', 'IOT_CLIENT_SECRET', 'IOT_PASSWORD')
            AND    value IS NOT NULL AND value <> dh_secret.c_mask AND secret_value IS NULL) LOOP
    dh_secret.set_secret(r.name, r.value);
  END LOOP;
  COMMIT;
END;
/

-- ---------------------------------------------------------------------------
-- Device settings of the OCI IoT Platform (scripts/README.md, IoT chapter):
--   domain short ID   IoT domain > Endpoint (device host), part before the first dot (step 3)
--   device password   content of the Vault secret dh-demo-device-pwd (step 4), stored encrypted
--   publish           Y: the simulation posts every reading to the IoT Platform
-- Press Enter to keep the current value (or to leave it empty for now).
-- Re-run this script, or only this block, when you have the values.
-- The password is typed hidden and, with VERIFY OFF, never echoed, so it does
-- not appear in a spool file either. It must not contain a single quote.
-- ---------------------------------------------------------------------------
SET VERIFY OFF
PROMPT
PROMPT == OCI IoT Platform settings (Enter = keep the current value / set later)
ACCEPT iot_region  CHAR DEFAULT 'eu-frankfurt-1' PROMPT 'OCI region [eu-frankfurt-1]: '
ACCEPT iot_ds      CHAR PROMPT 'IoT domain short ID (device host, part before the first dot): '
ACCEPT iot_pwd     CHAR PROMPT 'Device password (content of the Vault secret, hidden): ' HIDE
ACCEPT iot_publish CHAR PROMPT 'Publish readings to the IoT Platform, Y or N: '

MERGE INTO dh_config t
USING (
  SELECT 'IOT_DEVICE_HOST' AS name,
         CASE WHEN '&iot_ds' IS NOT NULL
              THEN LOWER('&iot_ds..device.iot.&iot_region..oci.oraclecloud.com') END AS value
  FROM dual
  UNION ALL
  SELECT 'IOT_PUBLISH', CASE WHEN UPPER('&iot_publish') IN ('Y', 'N') THEN UPPER('&iot_publish') END FROM dual
) s
ON (t.name = s.name)
WHEN MATCHED THEN UPDATE SET t.value = s.value
  WHERE s.value IS NOT NULL OR t.value LIKE '%<%'
WHEN NOT MATCHED THEN INSERT (name, value) VALUES (s.name, NVL(s.value, CASE s.name WHEN 'IOT_PUBLISH' THEN 'N' END));

BEGIN
  IF '&iot_pwd' IS NOT NULL THEN
    dh_secret.set_secret('IOT_DEVICE_PASSWORD', '&iot_pwd');
  END IF;
END;
/
COMMIT;
UNDEFINE iot_pwd

SELECT name, NVL(value, '(not set)') AS value
FROM   dh_config
WHERE  name IN ('IOT_DEVICE_HOST', 'IOT_DEVICE_PASSWORD', 'IOT_PUBLISH', 'INGEST_MODE')
ORDER  BY name;
