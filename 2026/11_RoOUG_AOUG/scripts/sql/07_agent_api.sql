-- =============================================================================
-- 07_agent_api.sql
--
-- Author:      Karin Patenge
-- Last update: 2026-10-27
--
-- Graph-powered tools for AI agents and for the APEX app.
--
--   Package DH_GRAPH_API  the logic (SQL/PGQ pattern matching + DBMS_OGA)
--   AGENT_* functions     thin, self-describing wrappers that return JSON.
--                         Register them in the Private Agent Factory
--                         "Oracle PL/SQL Executor" node (allowed routines).
--
-- Graph algorithms (DBMS_OGA) run through dynamic SQL, so the package also
-- compiles in databases without DBMS_OGA; results then come from SQL/PGQ only.
--
-- Note: static SQL in PL/SQL must not reference PL/SQL variables inside
-- GRAPH_TABLE (ORA-49028). Filters on parameters are therefore applied to the
-- COLUMNS output, outside the GRAPH_TABLE operator.
-- =============================================================================

CREATE OR REPLACE PACKAGE dh_graph_api AS
  FUNCTION network_status                                                    RETURN CLOB;
  FUNCTION active_anomalies   (p_min_severity   IN VARCHAR2 DEFAULT 'WATCH') RETURN CLOB;
  FUNCTION root_cause         (p_district       IN VARCHAR2 DEFAULT NULL)    RETURN CLOB;
  FUNCTION impact             (p_asset_id       IN VARCHAR2)                 RETURN CLOB;
  FUNCTION what_if            (p_out_of_service IN VARCHAR2,
                               p_open_valves    IN VARCHAR2 DEFAULT NULL)    RETURN CLOB;
  FUNCTION predict_failures   (p_horizon_hours  IN NUMBER   DEFAULT 240)     RETURN CLOB;
  FUNCTION critical_assets    (p_top            IN NUMBER   DEFAULT 5)       RETURN CLOB;
  FUNCTION asset_details      (p_asset_id       IN VARCHAR2)                 RETURN CLOB;
  FUNCTION maintenance_history(p_asset_id       IN VARCHAR2)                 RETURN CLOB;
  FUNCTION create_work_order  (p_asset_id       IN VARCHAR2,
                               p_priority       IN VARCHAR2,
                               p_title          IN VARCHAR2,
                               p_details        IN VARCHAR2 DEFAULT NULL,
                               p_created_by     IN VARCHAR2 DEFAULT 'AI_AGENT') RETURN CLOB;
  -- helpers (also used by APEX)
  FUNCTION oga_available RETURN BOOLEAN;
  FUNCTION unsupplied_buildings_json (p_out_of_service IN VARCHAR2, p_open_valves IN VARCHAR2) RETURN CLOB;
END dh_graph_api;
/

CREATE OR REPLACE PACKAGE BODY dh_graph_api AS

  g_oga VARCHAR2(1);   -- cached: Y / N

  FUNCTION oga_available RETURN BOOLEAN IS
    l_n NUMBER;
  BEGIN
    IF g_oga IS NULL THEN
      SELECT COUNT(*) INTO l_n FROM all_objects WHERE object_name = 'DBMS_OGA' AND object_type = 'PACKAGE';
      g_oga := CASE WHEN l_n > 0 THEN 'Y' ELSE 'N' END;
    END IF;
    RETURN g_oga = 'Y';
  END oga_available;

  -- add or replace a member of a JSON object (CLOB in, CLOB out)
  FUNCTION json_set (p_doc IN CLOB, p_key IN VARCHAR2, p_value IN CLOB) RETURN CLOB IS
    l_out CLOB;
  BEGIN
    SELECT JSON_MERGEPATCH(p_doc, JSON_OBJECT(KEY p_key VALUE p_value FORMAT JSON RETURNING CLOB) RETURNING CLOB)
    INTO   l_out FROM dual;
    RETURN l_out;
  END json_set;

  FUNCTION json_msg (p_key IN VARCHAR2, p_text IN VARCHAR2) RETURN CLOB IS
    l_out CLOB;
  BEGIN
    SELECT JSON_OBJECT(KEY p_key VALUE p_text RETURNING CLOB) INTO l_out FROM dual;
    RETURN l_out;
  END json_msg;

  -- ---------------------------------------------------------------------------
  FUNCTION network_status RETURN CLOB IS
    l_json CLOB;
  BEGIN
    SELECT JSON_OBJECT(
             'as_of_utc'               VALUE TO_CHAR(SYS_EXTRACT_UTC(SYSTIMESTAMP), 'YYYY-MM-DD"T"HH24:MI"Z"'),
             'city'                    VALUE (SELECT value FROM dh_config WHERE name = 'CITY'),
             'assets_by_health'        VALUE (SELECT JSON_ARRAYAGG(JSON_OBJECT('asset_type' VALUE asset_type,
                                                                               'health'     VALUE health_status,
                                                                               'count'      VALUE n)
                                                                   ORDER BY asset_type, health_status RETURNING CLOB)
                                              FROM (SELECT asset_type, health_status, COUNT(*) n
                                                    FROM dh_assets GROUP BY asset_type, health_status)) FORMAT JSON,
             'buildings_without_heat'  VALUE (SELECT COUNT(*) FROM dh_assets
                                              WHERE asset_type = 'BUILDING' AND health_status = 'ALARM'),
             'apartments_without_heat' VALUE (SELECT NVL(SUM(apartments), 0) FROM dh_assets
                                              WHERE asset_type = 'BUILDING' AND health_status = 'ALARM'),
             'critical_buildings_without_heat'
                                       VALUE (SELECT NVL(JSON_ARRAYAGG(name ORDER BY name RETURNING CLOB), TO_CLOB('[]'))
                                              FROM dh_assets
                                              WHERE asset_type = 'BUILDING' AND health_status = 'ALARM'
                                              AND criticality >= 4) FORMAT JSON,
             'districts_affected'      VALUE (SELECT NVL(JSON_ARRAYAGG(district ORDER BY district RETURNING CLOB), TO_CLOB('[]'))
                                              FROM (SELECT DISTINCT district FROM dh_assets
                                                    WHERE health_status IN ('WARNING', 'ALARM'))) FORMAT JSON,
             'open_anomalies'          VALUE (SELECT NVL(JSON_ARRAYAGG(JSON_OBJECT('severity' VALUE severity, 'count' VALUE n)
                                                                       RETURNING CLOB), TO_CLOB('[]'))
                                              FROM (SELECT severity, COUNT(*) n FROM dh_anomalies
                                                    WHERE status <> 'CLOSED' GROUP BY severity)) FORMAT JSON
             RETURNING CLOB)
    INTO   l_json
    FROM   dual;
    RETURN l_json;
  END network_status;

  -- ---------------------------------------------------------------------------
  FUNCTION active_anomalies (p_min_severity IN VARCHAR2 DEFAULT 'WATCH') RETURN CLOB IS
    l_json CLOB;
    l_min  NUMBER := CASE UPPER(p_min_severity) WHEN 'ALARM' THEN 3 WHEN 'WARNING' THEN 2 ELSE 1 END;
  BEGIN
    SELECT NVL(JSON_ARRAYAGG(
               JSON_OBJECT('anomaly_id'     VALUE an.anomaly_id,
                           'asset_id'       VALUE an.asset_id,
                           'asset_name'     VALUE a.name,
                           'asset_type'     VALUE a.asset_type,
                           'district'       VALUE a.district,
                           'metric'         VALUE an.metric,
                           'type'           VALUE an.anomaly_type,
                           'severity'       VALUE an.severity,
                           'hours_to_alarm' VALUE an.hours_to_alarm,
                           'details'        VALUE an.details,
                           'since_utc'      VALUE TO_CHAR(an.detected_at, 'YYYY-MM-DD"T"HH24:MI"Z"')
                           ABSENT ON NULL)
               ORDER BY DECODE(an.severity, 'ALARM', 3, 'WARNING', 2, 1) DESC, a.asset_type, an.asset_id
               RETURNING CLOB), TO_CLOB('[]'))
    INTO   l_json
    FROM   dh_anomalies an
    JOIN   dh_assets    a ON a.asset_id = an.asset_id
    WHERE  an.status <> 'CLOSED'
    AND    DECODE(an.severity, 'ALARM', 3, 'WARNING', 2, 1) >= l_min;
    RETURN json_set(json_msg('min_severity', UPPER(p_min_severity)), 'anomalies', l_json);
  END active_anomalies;

  -- ---------------------------------------------------------------------------
  -- Root cause: which anomalous upstream asset explains the cold buildings?
  --  1. SQL/PGQ: (anomaly) -detected_on-> (suspect) -supplies->{1,4} (cold building)
  --  2. each cold building goes to the suspect that explains the most buildings
  --  3. optional: Personalized PageRank (DBMS_OGA) from the symptomatic
  --     substations over the dependency graph confirms the ranking
  -- ---------------------------------------------------------------------------
  FUNCTION root_cause (p_district IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
    l_json   CLOB;
    l_ppr    CLOB;
    l_seeds  VARCHAR2(32767);
    l_sql    VARCHAR2(32767);
  BEGIN
    WITH links AS (       -- every (suspect, cold building) pair found by pattern matching
      SELECT suspect, cold_building, b_district, anomaly_type, hops
      FROM   GRAPH_TABLE (dh_network
               MATCH (an IS anomaly WHERE an.status <> 'CLOSED')
                     -[IS detected_on]-> (s IS asset)
                     -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
                     (b IS asset WHERE b.asset_type = 'BUILDING' AND b.health_status = 'ALARM')
               COLUMNS (s.asset_id     AS suspect,
                        b.asset_id     AS cold_building,
                        b.district     AS b_district,
                        an.anomaly_type AS anomaly_type,
                        COUNT(p.pipe_id) AS hops))
    ), explains AS (
      SELECT suspect, COUNT(DISTINCT cold_building) AS n_explained,
             MAX(CASE WHEN anomaly_type = 'FLATLINE' THEN 1 ELSE 0 END) AS has_flatline
      FROM   links GROUP BY suspect
    ), best AS (          -- the suspect explaining most buildings wins, then the most upstream one
      SELECT l.cold_building, l.suspect, e.has_flatline,
             ROW_NUMBER() OVER (PARTITION BY l.cold_building
                                ORDER BY e.n_explained DESC, e.has_flatline, l.hops DESC) AS rn
      FROM   links l JOIN explains e ON e.suspect = l.suspect
      WHERE  p_district IS NULL OR l.b_district = p_district
    ), incidents AS (
      SELECT b2.suspect,
             COUNT(DISTINCT b2.cold_building)         AS cold_buildings,
             SUM(NVL(bd.apartments, 0))               AS apartments,   -- rn = 1: one row per building
             MAX(b2.has_flatline)                     AS has_flatline
      FROM   best b2 JOIN dh_assets bd ON bd.asset_id = b2.cold_building
      WHERE  b2.rn = 1
      GROUP  BY b2.suspect
    )
    SELECT JSON_OBJECT(
      'scope'          VALUE NVL(p_district, 'whole network'),
      'cold_buildings' VALUE (SELECT COUNT(*) FROM dh_assets
                              WHERE asset_type = 'BUILDING' AND health_status = 'ALARM'
                              AND (p_district IS NULL OR district = p_district)),
      'incidents'      VALUE (SELECT NVL(JSON_ARRAYAGG(JSON_OBJECT(
                                 'root_cause_asset' VALUE i.suspect,
                                 'name'             VALUE a.name,
                                 'asset_type'       VALUE a.asset_type,
                                 'district'         VALUE a.district,
                                 'classification'   VALUE CASE WHEN i.has_flatline = 1
                                                               THEN 'SUSPECTED_SENSOR_FAULT'
                                                               ELSE 'EQUIPMENT_PROBLEM' END,
                                 'cold_buildings'   VALUE i.cold_buildings,
                                 'apartments'       VALUE i.apartments,
                                 'critical_buildings' VALUE (
                                     SELECT NVL(JSON_ARRAYAGG(bd.name ORDER BY bd.name RETURNING CLOB), TO_CLOB('[]'))
                                     FROM best b3 JOIN dh_assets bd ON bd.asset_id = b3.cold_building
                                     WHERE b3.rn = 1 AND b3.suspect = i.suspect AND bd.criticality >= 4) FORMAT JSON,
                                 'evidence'         VALUE (
                                     SELECT JSON_ARRAYAGG(an.anomaly_type || ' ' || an.severity || ': ' || an.details
                                                          ORDER BY DECODE(an.severity, 'ALARM', 3, 'WARNING', 2, 1) DESC
                                                          RETURNING CLOB)
                                     FROM dh_anomalies an
                                     WHERE an.asset_id = i.suspect AND an.status <> 'CLOSED') FORMAT JSON
                                 RETURNING CLOB) ORDER BY i.cold_buildings DESC RETURNING CLOB), TO_CLOB('[]'))
                              FROM incidents i JOIN dh_assets a ON a.asset_id = i.suspect) FORMAT JSON,
      'unexplained_cold_buildings' VALUE (
                              SELECT NVL(JSON_ARRAYAGG(b.asset_id ORDER BY b.asset_id RETURNING CLOB), TO_CLOB('[]'))
                              FROM dh_assets b
                              WHERE b.asset_type = 'BUILDING' AND b.health_status = 'ALARM'
                              AND (p_district IS NULL OR b.district = p_district)
                              AND b.asset_id NOT IN (SELECT cold_building FROM links)) FORMAT JSON
      RETURNING CLOB)
    INTO l_json
    FROM dual;

    -- Algorithmic confirmation: Personalized PageRank, seeded with the substations
    -- that feed cold buildings, walking "depends_on" edges upstream.
    IF oga_available THEN
      BEGIN
        SELECT JSON_ARRAYAGG(
                 JSON_OBJECT('GRAPH_OWNER' VALUE USER, 'GRAPH_NAME' VALUE 'DH_DEPENDENCY',
                             'ELEM_TABLE' VALUE 'DH_ASSETS_LIVE_V',
                             'KEY_VALUE' VALUE JSON_OBJECT('ASSET_ID' VALUE ss_id))
                 RETURNING VARCHAR2(32767))
        INTO   l_seeds
        FROM  (SELECT DISTINCT ss_id
               FROM GRAPH_TABLE (dh_dependency
                      MATCH (b IS asset WHERE b.asset_type = 'BUILDING' AND b.health_status = 'ALARM')
                            -[IS depends_on]-> (ss IS asset)
                      COLUMNS (ss.asset_id AS ss_id, b.district AS b_district))
               WHERE p_district IS NULL OR b_district = p_district);

        IF l_seeds IS NOT NULL THEN
          l_sql := q'[
            SELECT JSON_ARRAYAGG(JSON_OBJECT('asset_id' VALUE asset_id, 'asset_type' VALUE asset_type,
                                             'score' VALUE ROUND(rank, 4)) ORDER BY rank DESC RETURNING CLOB)
            FROM (SELECT asset_id, asset_type, rank
                  FROM GRAPH_TABLE (DBMS_OGA.PERSONALIZED_PAGERANK_SET(
                                      dh_dependency, PROPERTY(VERTEX OUTPUT rank),
                                      JSON('#SEEDS#'),
                                      100, 1e-6, 0.85d, FALSE)
                         MATCH (v IS asset WHERE v.asset_type IN ('PUMP_STATION', 'SUBSTATION'))   -- plants feed everything
                         COLUMNS (v.asset_id AS asset_id, v.asset_type AS asset_type, v.rank AS rank))
                  WHERE rank > 0                                    -- not reachable from the seeds
                  ORDER BY rank DESC
                  FETCH FIRST 5 ROWS ONLY)]';
          l_sql := REPLACE(l_sql, '#SEEDS#', REPLACE(l_seeds, '''', ''''''));
          EXECUTE IMMEDIATE l_sql INTO l_ppr;
          l_json := json_set(l_json, 'personalized_pagerank_top5', l_ppr);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        l_json := json_set(l_json, 'personalized_pagerank_note', json_msg('error', SUBSTR(SQLERRM, 1, 200)));
      END;
    END IF;
    RETURN l_json;
  END root_cause;

  -- ---------------------------------------------------------------------------
  -- Buildings without supply in a what-if scenario: pure SQL/PGQ on the live
  -- graph (views filtered by the DH_CTX scenario)
  -- ---------------------------------------------------------------------------
  FUNCTION unsupplied_buildings_json (p_out_of_service IN VARCHAR2, p_open_valves IN VARCHAR2) RETURN CLOB IS
    l_json CLOB;
  BEGIN
    dh_whatif.set_scenario(p_out_of_service, p_open_valves);

    WITH supplied AS (
      SELECT DISTINCT x_id
      FROM   GRAPH_TABLE (dh_live_network
               MATCH (pl IS asset WHERE pl.asset_type = 'PLANT') -[IS supplies]->{1,5}
                     (x IS asset WHERE x.asset_type = 'BUILDING')
               COLUMNS (x.asset_id AS x_id))
    ), cut AS (
      SELECT b.* FROM dh_assets b
      WHERE  b.asset_type = 'BUILDING'
      AND    b.asset_id NOT IN (SELECT x_id FROM supplied)
    )
    SELECT JSON_OBJECT(
             'out_of_service'           VALUE p_out_of_service,
             'open_valves'              VALUE p_open_valves,
             'buildings_without_supply' VALUE (SELECT COUNT(*) FROM cut),
             'apartments'               VALUE (SELECT NVL(SUM(apartments), 0) FROM cut),
             'critical_buildings'       VALUE (SELECT NVL(JSON_ARRAYAGG(name ORDER BY name RETURNING CLOB), TO_CLOB('[]'))
                                               FROM cut WHERE criticality >= 4) FORMAT JSON,
             'districts'                VALUE (SELECT NVL(JSON_ARRAYAGG(district ORDER BY district RETURNING CLOB), TO_CLOB('[]'))
                                               FROM (SELECT DISTINCT district FROM cut)) FORMAT JSON
             RETURNING CLOB)
    INTO   l_json
    FROM   dual;

    dh_whatif.clear;
    RETURN l_json;
  EXCEPTION WHEN OTHERS THEN
    dh_whatif.clear;
    RAISE;
  END unsupplied_buildings_json;

  -- ---------------------------------------------------------------------------
  FUNCTION impact (p_asset_id IN VARCHAR2) RETURN CLOB IS
    l_json     CLOB;
    l_options  CLOB := TO_CLOB('[]');
    l_result   CLOB;
    l_option   CLOB;
    l_name     dh_assets.name%TYPE;
  BEGIN
    -- The name is read first: a scalar subquery next to aggregates raises ORA-00937
    SELECT MAX(name) INTO l_name FROM dh_assets WHERE asset_id = p_asset_id;
    SELECT JSON_OBJECT(
             'asset_id'             VALUE p_asset_id,
             'asset_name'           VALUE l_name,
             'downstream_buildings' VALUE COUNT(DISTINCT b_id),
             'apartments'           VALUE NVL(SUM(apts), 0),
             'critical_buildings'   VALUE NVL(JSON_ARRAYAGG(CASE WHEN crit >= 4 THEN b_name END
                                                            ORDER BY b_name RETURNING CLOB), TO_CLOB('[]')) FORMAT JSON
             RETURNING CLOB)
    INTO   l_json
    FROM   GRAPH_TABLE (dh_network
             MATCH (s IS asset)
                   -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
                   (b IS asset WHERE b.asset_type = 'BUILDING')
             COLUMNS (s.asset_id AS s_id, b.asset_id AS b_id, b.name AS b_name,
                      b.apartments AS apts, b.criticality AS crit))
    WHERE  s_id = p_asset_id;

    l_json := json_set(l_json, 'if_asset_out_of_service', unsupplied_buildings_json(p_asset_id, NULL));

    -- Mitigation: closed bypass valves that lead into the affected area
    FOR v IN (
      SELECT p.pipe_id, p.from_asset, p.to_asset
      FROM   dh_pipes p
      WHERE  p.pipe_kind = 'BYPASS' AND p.valve_state = 'CLOSED'
      AND    p.from_asset <> p_asset_id
      AND    p.to_asset IN (SELECT d_id FROM GRAPH_TABLE (dh_network
                              MATCH (s IS asset)
                                    -[q IS supplies WHERE q.valve_state = 'OPEN']->{1,3} (d IS asset)
                              COLUMNS (s.asset_id AS s_id, d.asset_id AS d_id))
                            WHERE s_id = p_asset_id)
      ORDER BY p.pipe_id
    ) LOOP
      l_result := unsupplied_buildings_json(p_asset_id, v.pipe_id);
      SELECT JSON_OBJECT('action'          VALUE 'Open bypass valve ' || v.pipe_id || ' (' || v.from_asset || ' -> ' || v.to_asset || ')',
                         'result_if_out_of_service' VALUE l_result FORMAT JSON
                         RETURNING CLOB)
      INTO   l_option FROM dual;
      SELECT JSON_TRANSFORM(l_options, APPEND '$' = JSON(l_option) RETURNING CLOB) INTO l_options FROM dual;
    END LOOP;

    RETURN json_set(l_json, 'mitigation_options', l_options);
  END impact;

  -- ---------------------------------------------------------------------------
  FUNCTION what_if (p_out_of_service IN VARCHAR2, p_open_valves IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
    l_json    CLOB := unsupplied_buildings_json(p_out_of_service, p_open_valves);
    l_islands CLOB;
  BEGIN
    IF oga_available THEN
      BEGIN
        dh_whatif.set_scenario(p_out_of_service, p_open_valves);
        -- Weakly connected components: islands of the network without a heat plant
        EXECUTE IMMEDIATE q'~
          SELECT NVL(JSON_ARRAYAGG(JSON_OBJECT('component' VALUE comp, 'assets' VALUE n,
                                               'buildings' VALUE nb, 'feeding_asset' VALUE ex) RETURNING CLOB), TO_CLOB('[]'))
          FROM (SELECT comp, COUNT(*) n, SUM(CASE WHEN asset_type = 'BUILDING' THEN 1 ELSE 0 END) nb,
                       MIN(CASE WHEN asset_type <> 'BUILDING' THEN asset_id END) ex
                FROM GRAPH_TABLE (DBMS_OGA.WCC(dh_live_network, PROPERTY(VERTEX OUTPUT comp))
                       MATCH (a IS asset)
                       COLUMNS (a.asset_id AS asset_id, a.asset_type AS asset_type, a.comp AS comp))
                GROUP BY comp
                HAVING SUM(CASE WHEN asset_type = 'PLANT' THEN 1 ELSE 0 END) = 0)~'
        INTO l_islands;
        dh_whatif.clear;
        l_json := json_set(l_json, 'islands_without_plant_wcc', l_islands);
      EXCEPTION WHEN OTHERS THEN
        dh_whatif.clear;
        l_json := json_set(l_json, 'wcc_note', json_msg('error', SUBSTR(SQLERRM, 1, 200)));
      END;
    END IF;
    RETURN l_json;
  END what_if;

  -- ---------------------------------------------------------------------------
  FUNCTION predict_failures (p_horizon_hours IN NUMBER DEFAULT 240) RETURN CLOB IS
    l_json CLOB;
  BEGIN
    WITH dep AS (
      SELECT s_id, COUNT(DISTINCT b_id) AS nb
      FROM   GRAPH_TABLE (dh_network
               MATCH (s IS asset WHERE s.asset_type IN ('PUMP_STATION', 'SUBSTATION'))
                     -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
                     (b IS asset WHERE b.asset_type = 'BUILDING')
               COLUMNS (s.asset_id AS s_id, b.asset_id AS b_id))
      GROUP  BY s_id
    ), last_maint AS (     -- joined, not a scalar subquery inside the aggregate (ORA-00937)
      SELECT asset_id,
             MAX(maint_type || ' ' || TO_CHAR(performed_on, 'YYYY-MM-DD') || ': ' || description)
               KEEP (DENSE_RANK LAST ORDER BY performed_on) AS last_maintenance
      FROM   dh_maintenance
      GROUP  BY asset_id
    )
    SELECT NVL(JSON_ARRAYAGG(JSON_OBJECT(
               'asset_id'             VALUE a.asset_id,
               'asset_name'           VALUE a.name,
               'metric'               VALUE an.metric,
               'hours_to_alarm'       VALUE an.hours_to_alarm,
               'trend'                VALUE an.details,
               'dependent_buildings'  VALUE d.nb,
               'last_maintenance'     VALUE lm.last_maintenance
               ABSENT ON NULL RETURNING CLOB) ORDER BY an.hours_to_alarm RETURNING CLOB), TO_CLOB('[]'))
    INTO   l_json
    FROM   dh_anomalies an
    JOIN   dh_assets a ON a.asset_id = an.asset_id
    LEFT   JOIN dep d  ON d.s_id = a.asset_id
    LEFT   JOIN last_maint lm ON lm.asset_id = a.asset_id
    WHERE  an.status <> 'CLOSED'
    AND    an.anomaly_type = 'TREND'
    AND    an.hours_to_alarm <= p_horizon_hours
    AND    a.health_status <> 'ALARM';          -- already failed: not a prediction any more
    RETURN json_set(json_msg('horizon_hours', TO_CHAR(p_horizon_hours)), 'predictions', l_json);
  END predict_failures;

  -- ---------------------------------------------------------------------------
  -- Critical assets: how many buildings depend on an asset (SQL/PGQ) and
  -- PageRank on the dependency graph (DBMS_OGA)
  -- ---------------------------------------------------------------------------
  FUNCTION critical_assets (p_top IN NUMBER DEFAULT 5) RETURN CLOB IS
    l_json CLOB;
    l_pr   CLOB;
  BEGIN
    SELECT NVL(JSON_ARRAYAGG(JSON_OBJECT('asset_id' VALUE s_id, 'name' VALUE s_name, 'asset_type' VALUE s_type,
                                         'dependent_buildings' VALUE nb, 'apartments' VALUE apts,
                                         'critical_buildings' VALUE ncrit)
                             ORDER BY nb DESC, s_id RETURNING CLOB), TO_CLOB('[]'))
    INTO   l_json
    FROM  (SELECT s_id, s_name, s_type, COUNT(DISTINCT b_id) nb, SUM(apts) apts,
                  COUNT(DISTINCT CASE WHEN crit >= 4 THEN b_id END) ncrit
           FROM GRAPH_TABLE (dh_network
                  MATCH (s IS asset WHERE s.asset_type IN ('PLANT', 'PUMP_STATION'))
                        -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
                        (b IS asset WHERE b.asset_type = 'BUILDING')
                  COLUMNS (s.asset_id AS s_id, s.name AS s_name, s.asset_type AS s_type,
                           b.asset_id AS b_id, b.apartments AS apts, b.criticality AS crit))
           GROUP BY s_id, s_name, s_type
           ORDER BY nb DESC, s_id
           FETCH FIRST p_top ROWS ONLY);
    l_json := json_set(TO_CLOB('{}'), 'by_dependent_buildings', l_json);

    IF oga_available THEN
      BEGIN
        EXECUTE IMMEDIATE q'[
          SELECT JSON_ARRAYAGG(JSON_OBJECT('asset_id' VALUE asset_id, 'pagerank' VALUE ROUND(rank, 4))
                               ORDER BY rank DESC RETURNING CLOB)
          FROM (SELECT asset_id, rank
                FROM GRAPH_TABLE (DBMS_OGA.PAGERANK(dh_dependency, PROPERTY(VERTEX OUTPUT rank),
                                                    100, 1e-6, 0.85d, FALSE)
                       MATCH (v IS asset WHERE v.asset_type IN ('PUMP_STATION', 'SUBSTATION'))
                       COLUMNS (v.asset_id AS asset_id, v.rank AS rank))
                ORDER BY rank DESC
                FETCH FIRST :n ROWS ONLY)]'
        INTO l_pr USING p_top;
        l_json := json_set(l_json, 'by_pagerank', l_pr);
      EXCEPTION WHEN OTHERS THEN
        l_json := json_set(l_json, 'pagerank_note', json_msg('error', SUBSTR(SQLERRM, 1, 200)));
      END;
    END IF;
    RETURN l_json;
  END critical_assets;

  -- ---------------------------------------------------------------------------
  FUNCTION asset_details (p_asset_id IN VARCHAR2) RETURN CLOB IS
    l_json CLOB;
    l_id   dh_assets.asset_id%TYPE := UPPER(p_asset_id);
  BEGIN
    SELECT JSON_OBJECT(
             'asset_id' VALUE a.asset_id, 'name' VALUE a.name, 'asset_type' VALUE a.asset_type,
             'district' VALUE a.district, 'install_year' VALUE a.install_year, 'equipment' VALUE a.equipment,
             'health' VALUE a.health_status, 'health_reason' VALUE a.health_reason,
             'latest_values' VALUE (
                SELECT JSON_ARRAYAGG(JSON_OBJECT('metric' VALUE m.display_name, 'value' VALUE ROUND(t.value, 2),
                                                 'unit' VALUE m.unit,
                                                 'at_utc' VALUE TO_CHAR(t.ts, 'YYYY-MM-DD"T"HH24:MI"Z"')) RETURNING CLOB)
                FROM (SELECT metric, MAX(ts) ts, MAX(value) KEEP (DENSE_RANK LAST ORDER BY ts) value
                      FROM dh_telemetry
                      WHERE asset_id = l_id AND ts > SYS_EXTRACT_UTC(SYSTIMESTAMP) - INTERVAL '1' HOUR
                      GROUP BY metric) t
                JOIN dh_metrics m ON m.asset_type = a.asset_type AND m.metric = t.metric) FORMAT JSON,
             'supplied_by' VALUE (
                SELECT JSON_ARRAYAGG(up_id || ' (' || up_type || ', ' || hops || ' hop' ||
                                     CASE WHEN hops > 1 THEN 's' END || ')' ORDER BY hops RETURNING CLOB)
                FROM GRAPH_TABLE (dh_network
                       MATCH (u IS asset) -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4} (x IS asset)
                       COLUMNS (u.asset_id AS up_id, u.asset_type AS up_type, x.asset_id AS x_id,
                                COUNT(p.pipe_id) AS hops))
                WHERE x_id = l_id) FORMAT JSON,
             'open_work_orders' VALUE (
                SELECT JSON_ARRAYAGG(JSON_OBJECT('wo_id' VALUE w.wo_id, 'priority' VALUE w.priority,
                                                 'title' VALUE w.title, 'status' VALUE w.status) RETURNING CLOB)
                FROM dh_work_orders w WHERE w.asset_id = a.asset_id AND w.status IN ('NEW', 'PLANNED')) FORMAT JSON
             ABSENT ON NULL RETURNING CLOB)
    INTO   l_json
    FROM   dh_assets a
    WHERE  a.asset_id = l_id;
    RETURN l_json;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RETURN json_msg('error', 'Unknown asset ' || p_asset_id);
  END asset_details;

  -- ---------------------------------------------------------------------------
  FUNCTION maintenance_history (p_asset_id IN VARCHAR2) RETURN CLOB IS
    l_json CLOB;
  BEGIN
    SELECT NVL(JSON_ARRAYAGG(JSON_OBJECT('date'           VALUE TO_CHAR(performed_on, 'YYYY-MM-DD'),
                                         'type'           VALUE maint_type,
                                         'description'    VALUE description,
                                         'downtime_hours' VALUE downtime_hours)
                             ORDER BY performed_on DESC RETURNING CLOB), TO_CLOB('[]'))
    INTO   l_json
    FROM   dh_maintenance
    WHERE  asset_id = UPPER(p_asset_id);
    RETURN json_set(json_msg('asset_id', UPPER(p_asset_id)), 'history', l_json);
  END maintenance_history;

  -- ---------------------------------------------------------------------------
  FUNCTION create_work_order (p_asset_id   IN VARCHAR2,
                              p_priority   IN VARCHAR2,
                              p_title      IN VARCHAR2,
                              p_details    IN VARCHAR2 DEFAULT NULL,
                              p_created_by IN VARCHAR2 DEFAULT 'AI_AGENT') RETURN CLOB IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    l_id      dh_work_orders.wo_id%TYPE;
    l_anomaly dh_anomalies.anomaly_id%TYPE;
    l_json    CLOB;
  BEGIN
    SELECT MAX(anomaly_id) KEEP (DENSE_RANK LAST ORDER BY DECODE(severity, 'ALARM', 3, 'WARNING', 2, 1), detected_at)
    INTO   l_anomaly
    FROM   dh_anomalies
    WHERE  asset_id = UPPER(p_asset_id) AND status <> 'CLOSED';

    INSERT INTO dh_work_orders (asset_id, anomaly_id, priority, title, details, created_by)
    VALUES (UPPER(p_asset_id), l_anomaly, UPPER(p_priority), SUBSTRB(p_title, 1, 200), p_details, p_created_by)
    RETURNING wo_id INTO l_id;
    COMMIT;

    SELECT JSON_OBJECT('wo_id' VALUE l_id, 'asset_id' VALUE UPPER(p_asset_id), 'priority' VALUE UPPER(p_priority),
                       'linked_anomaly_id' VALUE l_anomaly, 'status' VALUE 'NEW' RETURNING CLOB)
    INTO   l_json FROM dual;
    RETURN l_json;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RETURN json_msg('error', SUBSTR(SQLERRM, 1, 300));
  END create_work_order;

END dh_graph_api;
/

-- =============================================================================
-- Agent tools: one function per tool, descriptive names and parameters.
-- =============================================================================
CREATE OR REPLACE FUNCTION agent_network_status RETURN CLOB IS
BEGIN RETURN dh_graph_api.network_status; END;
/
CREATE OR REPLACE FUNCTION agent_active_anomalies (p_min_severity IN VARCHAR2 DEFAULT 'WATCH') RETURN CLOB IS
BEGIN RETURN dh_graph_api.active_anomalies(p_min_severity); END;
/
CREATE OR REPLACE FUNCTION agent_find_root_cause (p_district IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
BEGIN RETURN dh_graph_api.root_cause(p_district); END;
/
CREATE OR REPLACE FUNCTION agent_impact_analysis (p_asset_id IN VARCHAR2) RETURN CLOB IS
BEGIN RETURN dh_graph_api.impact(UPPER(p_asset_id)); END;
/
CREATE OR REPLACE FUNCTION agent_what_if (p_out_of_service IN VARCHAR2, p_open_valves IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
BEGIN RETURN dh_graph_api.what_if(p_out_of_service, p_open_valves); END;
/
CREATE OR REPLACE FUNCTION agent_predict_failures (p_horizon_hours IN NUMBER DEFAULT 240) RETURN CLOB IS
BEGIN RETURN dh_graph_api.predict_failures(p_horizon_hours); END;
/
CREATE OR REPLACE FUNCTION agent_critical_assets (p_top IN NUMBER DEFAULT 5) RETURN CLOB IS
BEGIN RETURN dh_graph_api.critical_assets(p_top); END;
/
CREATE OR REPLACE FUNCTION agent_asset_details (p_asset_id IN VARCHAR2) RETURN CLOB IS
BEGIN RETURN dh_graph_api.asset_details(p_asset_id); END;
/
CREATE OR REPLACE FUNCTION agent_maintenance_history (p_asset_id IN VARCHAR2) RETURN CLOB IS
BEGIN RETURN dh_graph_api.maintenance_history(p_asset_id); END;
/
CREATE OR REPLACE FUNCTION agent_create_work_order (p_asset_id IN VARCHAR2, p_priority IN VARCHAR2,
                                                    p_title IN VARCHAR2, p_details IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
BEGIN RETURN dh_graph_api.create_work_order(p_asset_id, p_priority, p_title, p_details, 'AI_AGENT'); END;
/
