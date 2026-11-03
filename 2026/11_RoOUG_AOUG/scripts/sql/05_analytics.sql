-- =============================================================================
-- 05_analytics.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-10-27
--
-- Package DH_ANALYTICS: anomaly detection and health status, in SQL.
--
--   THRESHOLD  2-minute average outside warning / alarm limits (dh_metrics)
--   ZSCORE     2-minute average far from the 7-day baseline (|z| >= 4)
--   TREND      predictive: hourly trend of the last 72 h, hours until the
--              alarm limit is reached (vibration, bearing temperature)
--   FLATLINE   sensor reports the same value for 30 minutes
--   NO_DATA    twin silent for 10 minutes
--
-- Health: pump stations and substations take the worst open anomaly;
-- buildings are "cold" (ALARM) when their substation delivers < 50 °C
-- (1-minute average).
--
-- Timing (readings every 30 s): an action such as a pump trip or an opened
-- bypass shows in the building status within about 1.5 minutes and in the
-- anomalies within about 2 minutes. A finding that is no longer seen closes
-- after 1 minute. The 2-minute window for limits keeps noise from causing
-- short false warnings (e.g. PS-08 vibration runs close to its warning limit).
--
-- Numbers in the texts are formatted explicitly, so they read the same whatever
-- the NLS settings of the session or the scheduler job: "." as the decimal
-- separator, a leading zero, no trailing zeros. The pattern is
--   RTRIM(TO_CHAR(ROUND(x, 1), 'FM999999990.9'), '.')     0.45 -> 0.5, 41.0 -> 41
-- ("." in a format model is always a period; "D" would follow NLS). It is
-- written inline on purpose: a PL/SQL function in these GROUP BY statements
-- failed at run time with ORA-00979 in 26ai.
--
-- Production option: replace the SQL statistics with Oracle Machine Learning
-- (for example the MSET-SPRT anomaly detection algorithm) - same tables.
-- =============================================================================

CREATE OR REPLACE PACKAGE dh_analytics AS
  PROCEDURE detect        (p_now IN TIMESTAMP DEFAULT NULL);
  PROCEDURE update_health (p_now IN TIMESTAMP DEFAULT NULL);
  -- detect + update_health, called by the scheduler job every minute
  PROCEDURE run           (p_now IN TIMESTAMP DEFAULT NULL);
END dh_analytics;
/

CREATE OR REPLACE PACKAGE BODY dh_analytics AS

  FUNCTION now_utc (p_now IN TIMESTAMP) RETURN TIMESTAMP IS
    l_ts TIMESTAMP(3);
  BEGIN
    IF p_now IS NOT NULL THEN
      RETURN p_now;
    END IF;
    SELECT CAST(SYS_EXTRACT_UTC(SYSTIMESTAMP) AS TIMESTAMP(3)) INTO l_ts FROM dual;   -- in SQL, not in PL/SQL
    RETURN l_ts;
  END now_utc;

  PROCEDURE detect (p_now IN TIMESTAMP DEFAULT NULL) IS
    l_now TIMESTAMP(3) := now_utc(p_now);
  BEGIN
    MERGE INTO dh_anomalies a
    USING (
      WITH cur AS (            -- current state: 2-minute average per asset and metric
        SELECT asset_id, metric, AVG(value) AS val, COUNT(*) AS n
        FROM   dh_telemetry
        WHERE  ts >  l_now - INTERVAL '2' MINUTE
        AND    ts <= l_now
        GROUP  BY asset_id, metric
      ), base AS (             -- baseline: 7 days, without the last 2 hours
        SELECT asset_id, metric, AVG(value) AS mu, STDDEV(value) AS sigma
        FROM   dh_telemetry
        WHERE  ts >  l_now - INTERVAL '7' DAY
        AND    ts <= l_now - INTERVAL '2' HOUR
        GROUP  BY asset_id, metric
      ), thr AS (
        SELECT c.asset_id, c.metric, 'THRESHOLD' AS anomaly_type,
               CASE WHEN c.val >= m.alarm_high OR c.val <= m.alarm_low THEN 'ALARM' ELSE 'WARNING' END AS severity,
               c.val AS observed_value, m.normal_value AS expected_value,
               CAST(NULL AS NUMBER) AS score, CAST(NULL AS NUMBER) AS hours_to_alarm,
               m.display_name || ' ' || RTRIM(TO_CHAR(ROUND(c.val, 1), 'FM999999990.9'), '.') || ' ' || m.unit ||
               CASE WHEN c.val >= LEAST(NVL(m.warn_high, 1e99), NVL(m.alarm_high, 1e99))
                    THEN ' (above ' || CASE WHEN c.val >= m.alarm_high THEN 'alarm ' || RTRIM(TO_CHAR(ROUND(m.alarm_high, 2), 'FM999999990.99'), '.')
                                            ELSE 'warning ' || RTRIM(TO_CHAR(ROUND(m.warn_high, 2), 'FM999999990.99'), '.') END || ')'
                    ELSE ' (below ' || CASE WHEN c.val <= m.alarm_low THEN 'alarm ' || RTRIM(TO_CHAR(ROUND(m.alarm_low, 2), 'FM999999990.99'), '.')
                                            ELSE 'warning ' || RTRIM(TO_CHAR(ROUND(m.warn_low, 2), 'FM999999990.99'), '.') END || ')'
               END AS details
        FROM   cur c
        JOIN   dh_assets  s ON s.asset_id = c.asset_id
        JOIN   dh_metrics m ON m.asset_type = s.asset_type AND m.metric = c.metric
        WHERE  c.val >= LEAST(NVL(m.warn_high, 1e99), NVL(m.alarm_high, 1e99))
        OR     c.val <= GREATEST(NVL(m.warn_low, -1e99), NVL(m.alarm_low, -1e99))
      ), zsc (asset_id, metric, anomaly_type, severity, observed_value, expected_value, score, hours_to_alarm, details) AS (
        SELECT c.asset_id, c.metric, 'ZSCORE', 'WARNING',
               c.val, b.mu, ROUND((c.val - b.mu) / b.sigma, 2), CAST(NULL AS NUMBER),
               m.display_name || ' ' || RTRIM(TO_CHAR(ROUND(c.val, 1), 'FM999999990.9'), '.') || ' ' || m.unit || ' vs. 7-day mean ' ||
               RTRIM(TO_CHAR(ROUND(b.mu, 1), 'FM999999990.9'), '.') || ' (z = ' || RTRIM(TO_CHAR(ROUND((c.val - b.mu) / b.sigma, 1), 'FM999999990.9'), '.') || ')'
        FROM   cur c
        JOIN   base b ON b.asset_id = c.asset_id AND b.metric = c.metric
        JOIN   dh_assets  s ON s.asset_id = c.asset_id
        JOIN   dh_metrics m ON m.asset_type = s.asset_type AND m.metric = c.metric
        WHERE  b.sigma > 0
        AND    ABS(c.val - b.mu) / b.sigma >= 4
        AND    NOT EXISTS (SELECT 1 FROM thr t WHERE t.asset_id = c.asset_id AND t.metric = c.metric)
      ), hourly AS (
        SELECT t.asset_id, t.metric,
               (CAST(TRUNC(t.ts, 'HH') AS DATE) - CAST(l_now AS DATE)) * 24 AS hx,   -- hours, negative
               AVG(t.value) AS v
        FROM   dh_telemetry t
        JOIN   dh_assets  s ON s.asset_id = t.asset_id
        JOIN   dh_metrics m ON m.asset_type = s.asset_type AND m.metric = t.metric AND m.predict = 'Y'
        WHERE  t.ts > l_now - INTERVAL '72' HOUR
        GROUP  BY t.asset_id, t.metric, TRUNC(t.ts, 'HH')
      ), reg AS (
        SELECT asset_id, metric, REGR_SLOPE(v, hx) AS slope, REGR_R2(v, hx) AS r2,
               REGR_INTERCEPT(v, hx) AS v_now
        FROM   hourly
        GROUP  BY asset_id, metric
        HAVING COUNT(*) >= 24
      ), trd (asset_id, metric, anomaly_type, severity, observed_value, expected_value, score, hours_to_alarm, details) AS (
        SELECT r.asset_id, r.metric, 'TREND',
               CASE WHEN (m.alarm_high - r.v_now) / r.slope <= 24 THEN 'WARNING' ELSE 'WATCH' END,
               r.v_now, m.normal_value, ROUND(r.slope, 4),
               ROUND((m.alarm_high - r.v_now) / r.slope, 1),
               m.display_name || ' rising ' || RTRIM(TO_CHAR(ROUND(r.slope * 24, 2), 'FM999999990.99'), '.') || ' ' || m.unit ||
               '/day, alarm limit ' || RTRIM(TO_CHAR(ROUND(m.alarm_high, 2), 'FM999999990.99'), '.')
               || ' in ~' || TO_CHAR(ROUND((m.alarm_high - r.v_now) / r.slope), 'FM999999990') || ' h'
        FROM   reg r
        JOIN   dh_assets  s ON s.asset_id = r.asset_id
        JOIN   dh_metrics m ON m.asset_type = s.asset_type AND m.metric = r.metric
        WHERE  r.slope > 0 AND r.r2 >= 0.6
        AND    r.v_now < m.alarm_high
        AND    (m.alarm_high - r.v_now) / r.slope <= 240          -- 10-day horizon
      ), flat (asset_id, metric, anomaly_type, severity, observed_value, expected_value, score, hours_to_alarm, details) AS (
        SELECT t.asset_id, t.metric, 'FLATLINE', 'WATCH',
               MAX(t.value), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
               'Sensor ' || t.metric || ' constant at ' || RTRIM(TO_CHAR(ROUND(MAX(t.value), 3), 'FM999999990.999'), '.') || ' for 30 min (stuck sensor?)'
        FROM   dh_telemetry t
        WHERE  t.ts > l_now - INTERVAL '30' MINUTE AND t.ts <= l_now
        GROUP  BY t.asset_id, t.metric
        HAVING COUNT(*) >= 5 AND MIN(t.value) = MAX(t.value)
      ), silent (asset_id, metric, anomaly_type, severity, observed_value, expected_value, score, hours_to_alarm, details) AS (
        SELECT s.asset_id, '*', 'NO_DATA', 'WARNING',
               CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
               'No telemetry for 10 minutes'
        FROM   dh_assets s
        WHERE  s.asset_type IN ('PUMP_STATION', 'SUBSTATION')
        AND    NOT EXISTS (SELECT 1 FROM dh_telemetry t
                           WHERE t.asset_id = s.asset_id AND t.ts > l_now - INTERVAL '10' MINUTE)
      )
      SELECT * FROM thr
      UNION ALL SELECT * FROM zsc
      UNION ALL SELECT * FROM trd
      UNION ALL SELECT * FROM flat
      UNION ALL SELECT * FROM silent
    ) f
    ON (a.asset_id = f.asset_id AND a.metric = f.metric AND a.anomaly_type = f.anomaly_type AND a.status <> 'CLOSED')
    WHEN MATCHED THEN UPDATE SET
      a.severity       = f.severity,
      a.last_seen_at   = l_now,
      a.observed_value = f.observed_value,
      a.expected_value = f.expected_value,
      a.score          = f.score,
      a.hours_to_alarm = f.hours_to_alarm,
      a.details        = SUBSTRB(f.details, 1, 400)
    WHEN NOT MATCHED THEN INSERT
      (asset_id, metric, anomaly_type, severity, status, detected_at, last_seen_at,
       observed_value, expected_value, score, hours_to_alarm, details)
    VALUES
      (f.asset_id, f.metric, f.anomaly_type, f.severity, 'OPEN', l_now, l_now,
       f.observed_value, f.expected_value, f.score, f.hours_to_alarm, SUBSTRB(f.details, 1, 400));

    -- Close what has not been seen for 1 minute (two runs of the job)
    UPDATE dh_anomalies
    SET    status = 'CLOSED'
    WHERE  status <> 'CLOSED'
    AND    last_seen_at < l_now - INTERVAL '1' MINUTE;

    -- A z-score finding is superseded as soon as the same metric crosses a
    -- limit: close it at once, so the evidence does not show an outdated value
    UPDATE dh_anomalies z
    SET    z.status = 'CLOSED'
    WHERE  z.anomaly_type = 'ZSCORE' AND z.status <> 'CLOSED'
    AND    EXISTS (SELECT 1 FROM dh_anomalies t
                   WHERE  t.asset_id = z.asset_id AND t.metric = z.metric
                   AND    t.anomaly_type = 'THRESHOLD' AND t.status <> 'CLOSED');
  END detect;

  PROCEDURE update_health (p_now IN TIMESTAMP DEFAULT NULL) IS
    l_now TIMESTAMP(3) := now_utc(p_now);
  BEGIN
    -- Pump stations and substations: worst open anomaly
    MERGE INTO dh_assets s
    USING (
      SELECT x.asset_id,
             NVL(DECODE(MAX(DECODE(an.severity, 'ALARM', 3, 'WARNING', 2, 'WATCH', 1)),
                        3, 'ALARM', 2, 'WARNING', 1, 'WATCH'), 'OK') AS health_status,
             SUBSTRB(LISTAGG(an.details, '; ' ON OVERFLOW TRUNCATE)
                      WITHIN GROUP (ORDER BY DECODE(an.severity, 'ALARM', 3, 'WARNING', 2, 1) DESC), 1, 400) AS health_reason
      FROM   dh_assets x
      LEFT   JOIN dh_anomalies an ON an.asset_id = x.asset_id AND an.status <> 'CLOSED'
      WHERE  x.asset_type IN ('PUMP_STATION', 'SUBSTATION')
      GROUP  BY x.asset_id
    ) h
    ON (s.asset_id = h.asset_id)
    WHEN MATCHED THEN UPDATE SET
      s.health_status  = h.health_status,
      s.health_reason  = h.health_reason,
      s.health_updated = l_now;

    -- Buildings: heat delivered by their substation (secondary supply temperature)
    MERGE INTO dh_assets b
    USING (
      SELECT p.to_asset AS asset_id,
             CASE WHEN t.val < 50 THEN 'ALARM' WHEN t.val < 55 THEN 'WARNING' ELSE 'OK' END AS health_status,
             CASE WHEN t.val < 55 THEN 'Heat supply ' || RTRIM(TO_CHAR(ROUND(t.val, 1), 'FM999999990.9'), '.') || ' °C from ' || p.from_asset END AS health_reason
      FROM   dh_pipes p
      JOIN   dh_assets b2 ON b2.asset_id = p.to_asset AND b2.asset_type = 'BUILDING'
      JOIN  (SELECT asset_id, AVG(value) AS val
             FROM   dh_telemetry
             WHERE  metric = 't_sec' AND ts > l_now - INTERVAL '1' MINUTE AND ts <= l_now
             GROUP  BY asset_id) t
        ON   t.asset_id = p.from_asset
    ) h
    ON (b.asset_id = h.asset_id)
    WHEN MATCHED THEN UPDATE SET
      b.health_status  = h.health_status,
      b.health_reason  = h.health_reason,
      b.health_updated = l_now;
  END update_health;

  PROCEDURE run (p_now IN TIMESTAMP DEFAULT NULL) IS
  BEGIN
    detect(p_now);
    update_health(p_now);
    COMMIT;
  END run;

END dh_analytics;
/
