-- =============================================================================
-- 06_iot_sync.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-11-03
--
-- Package DH_IOT_SYNC: pulls historized telemetry from the OCI IoT Platform
-- (IoT Data API, served by ORDS of the IoT domain group) into DH_TELEMETRY.
--
-- Optional. Used only with INGEST_MODE = IOT, which needs an OAuth application
-- and a user in an identity domain (scripts/README.md, optional steps). The
-- default path (INGEST_MODE = DIRECT) does not need this package: the database
-- device simulation (06b_device_sim.sql) writes its readings directly.
--
--   1. OAuth token from the identity domain (confidential app, password grant,
--      scope /<domain-group-short-id>/iot/<domain-short-id>)
--   2. GET .../20250531/historizedData?q={time_observed > high-water mark}
--   3. map digital_twin_instance_id -> dh_assets.twin_ocid,
--      content_path -> metric, value -> number
--
-- Configure in DH_CONFIG (scripts/README.md, optional chapter, step C). Test once by hand:
--   EXEC dh_iot_sync.pull(p_verbose => TRUE);
--
-- Before the session, check the JSON field names of one /historizedData
-- response with curl; adjust c_* paths if needed.
-- =============================================================================

CREATE OR REPLACE PACKAGE dh_iot_sync AS
  FUNCTION  get_token RETURN VARCHAR2;
  -- returns number of rows merged
  FUNCTION  pull_rows (p_max_pages IN PLS_INTEGER DEFAULT 20, p_verbose IN BOOLEAN DEFAULT FALSE) RETURN NUMBER;
  PROCEDURE pull (p_max_pages IN PLS_INTEGER DEFAULT 20, p_verbose IN BOOLEAN DEFAULT FALSE);
END dh_iot_sync;
/

CREATE OR REPLACE PACKAGE BODY dh_iot_sync AS

  g_token     VARCHAR2(32767);
  g_token_exp DATE;
  -- The ampersand is written as CHR(38): a literal one would make SQLcl and
  -- SQL*Plus prompt for substitution variables (scope, limit, ...) on install
  c_amp       CONSTANT VARCHAR2(1) := CHR(38);

  FUNCTION cfg (p_name IN VARCHAR2) RETURN VARCHAR2 IS
    l_value dh_config.value%TYPE;
  BEGIN
    SELECT value INTO l_value FROM dh_config WHERE name = p_name;
    RETURN l_value;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
  END cfg;

  PROCEDURE set_cfg (p_name IN VARCHAR2, p_value IN VARCHAR2) IS
  BEGIN
    -- the row may not exist yet: the pull settings are only created when used
    MERGE INTO dh_config c USING (SELECT p_name AS name, p_value AS value FROM dual) s
    ON (c.name = s.name)
    WHEN MATCHED THEN UPDATE SET c.value = s.value
    WHEN NOT MATCHED THEN INSERT (name, value) VALUES (s.name, s.value);
  END set_cfg;

  FUNCTION b64 (p_text IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN REPLACE(REPLACE(UTL_RAW.CAST_TO_VARCHAR2(
             UTL_ENCODE.BASE64_ENCODE(UTL_RAW.CAST_TO_RAW(p_text))), CHR(13)), CHR(10));
  END b64;

  FUNCTION esc (p_text IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN UTL_URL.ESCAPE(p_text, TRUE, 'AL32UTF8');
  END esc;

  FUNCTION get_token RETURN VARCHAR2 IS
    l_resp CLOB;
  BEGIN
    IF g_token IS NOT NULL AND g_token_exp > SYSDATE + 1/1440 THEN
      RETURN g_token;
    END IF;

    APEX_WEB_SERVICE.CLEAR_REQUEST_HEADERS;
    APEX_WEB_SERVICE.SET_REQUEST_HEADERS(
      p_name_01  => 'Content-Type',  p_value_01 => 'application/x-www-form-urlencoded',
      p_name_02  => 'Authorization', p_value_02 => 'Basic ' || b64(cfg('IOT_CLIENT_ID') || ':' || dh_secret.get_secret('IOT_CLIENT_SECRET')));

    l_resp := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
                p_url         => cfg('IOT_TOKEN_URL'),
                p_http_method => 'POST',
                p_body        => 'grant_type=password'
                              || c_amp || 'scope='    || esc(cfg('IOT_SCOPE'))
                              || c_amp || 'username=' || esc(cfg('IOT_USER'))
                              || c_amp || 'password=' || esc(dh_secret.get_secret('IOT_PASSWORD')));

    IF APEX_WEB_SERVICE.G_STATUS_CODE <> 200 THEN
      RAISE_APPLICATION_ERROR(-20100, 'Token request failed: HTTP ' || APEX_WEB_SERVICE.G_STATUS_CODE
                                      || ' ' || DBMS_LOB.SUBSTR(l_resp, 300, 1));
    END IF;

    g_token     := JSON_VALUE(l_resp, '$.access_token' RETURNING VARCHAR2(32767));
    g_token_exp := SYSDATE + NVL(JSON_VALUE(l_resp, '$.expires_in' RETURNING NUMBER), 3600) / 86400;
    RETURN g_token;
  END get_token;

  FUNCTION pull_rows (p_max_pages IN PLS_INTEGER DEFAULT 20, p_verbose IN BOOLEAN DEFAULT FALSE) RETURN NUMBER IS
    l_base    VARCHAR2(1000) := cfg('IOT_DATA_API_BASE');
    l_since   VARCHAR2(40)   := NVL(cfg('IOT_LAST_TS'),
                                    TO_CHAR(SYS_EXTRACT_UTC(SYSTIMESTAMP) - INTERVAL '15' MINUTE,
                                            'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'));
    l_limit   PLS_INTEGER    := NVL(TO_NUMBER(cfg('IOT_PAGE_SIZE')), 500);
    l_offset  PLS_INTEGER    := 0;
    l_resp    CLOB;
    l_q       VARCHAR2(1000);
    l_rows    NUMBER := 0;
    l_page    NUMBER;
    l_more    VARCHAR2(10);
    l_max_ts  VARCHAR2(40);
  BEGIN
    l_q := '{"time_observed":{"$gt":{"$date":"' || l_since || '"}},"$orderby":{"time_observed":"ASC"}}';

    FOR i IN 1 .. p_max_pages LOOP
      APEX_WEB_SERVICE.CLEAR_REQUEST_HEADERS;
      APEX_WEB_SERVICE.SET_REQUEST_HEADERS(p_name_01 => 'Authorization', p_value_01 => 'Bearer ' || get_token);

      l_resp := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
                  p_url         => l_base || '/historizedData?q=' || esc(l_q)
                                          || c_amp || 'limit=' || l_limit || c_amp || 'offset=' || l_offset,
                  p_http_method => 'GET');

      IF APEX_WEB_SERVICE.G_STATUS_CODE <> 200 THEN
        RAISE_APPLICATION_ERROR(-20101, 'historizedData failed: HTTP ' || APEX_WEB_SERVICE.G_STATUS_CODE
                                        || ' ' || DBMS_LOB.SUBSTR(l_resp, 300, 1));
      END IF;

      MERGE INTO dh_telemetry t
      USING (
        SELECT a.asset_id,
               j.content_path AS metric,
               CAST(TO_UTC_TIMESTAMP_TZ(j.time_observed) AS TIMESTAMP(3)) AS ts,
               j.val          AS value
        FROM   JSON_TABLE(l_resp, '$.items[*]'
                 COLUMNS (twin_id       VARCHAR2(255) PATH '$.digital_twin_instance_id',
                          content_path  VARCHAR2(100) PATH '$.content_path',
                          val           NUMBER        PATH '$.value'  NULL ON ERROR,
                          time_observed VARCHAR2(40)  PATH '$.time_observed')) j
        JOIN   dh_assets a ON a.twin_ocid = j.twin_id
        WHERE  j.val IS NOT NULL
      ) s
      ON (t.asset_id = s.asset_id AND t.metric = s.metric AND t.ts = s.ts)
      WHEN NOT MATCHED THEN INSERT (asset_id, metric, ts, value, source)
                            VALUES (s.asset_id, s.metric, s.ts, s.value, 'IOT');
      l_rows := l_rows + SQL%ROWCOUNT;

      SELECT COUNT(*), MAX(time_observed)
      INTO   l_page, l_max_ts
      FROM   JSON_TABLE(l_resp, '$.items[*]' COLUMNS (time_observed VARCHAR2(40) PATH '$.time_observed'));
      l_more := JSON_VALUE(l_resp, '$.hasMore');

      IF l_max_ts IS NOT NULL THEN
        set_cfg('IOT_LAST_TS', l_max_ts);   -- ISO strings sort chronologically
      END IF;
      IF p_verbose THEN
        DBMS_OUTPUT.PUT_LINE('page ' || i || ': ' || l_page || ' items, hasMore=' || l_more || ', last ' || l_max_ts);
      END IF;

      EXIT WHEN l_more IS NULL OR l_more <> 'true' OR l_page = 0;
      l_offset := l_offset + l_page;
    END LOOP;

    COMMIT;
    RETURN l_rows;
  END pull_rows;

  PROCEDURE pull (p_max_pages IN PLS_INTEGER DEFAULT 20, p_verbose IN BOOLEAN DEFAULT FALSE) IS
    l_rows NUMBER;
  BEGIN
    l_rows := pull_rows(p_max_pages, p_verbose);
    IF p_verbose THEN DBMS_OUTPUT.PUT_LINE(l_rows || ' rows merged'); END IF;
  END pull;

END dh_iot_sync;
/
