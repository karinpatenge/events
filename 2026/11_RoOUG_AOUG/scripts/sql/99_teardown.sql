-- =============================================================================
-- 99_teardown.sql - removes all demo objects from the demo schema (OGBEMEA2026)
--
-- Author:      Karin Patenge
-- Last update: 2026-10-28
--
-- =============================================================================
BEGIN DBMS_SCHEDULER.DROP_JOB('DH_TICK_JOB', force => TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN
  FOR g IN (SELECT graph_name FROM user_property_graphs WHERE graph_name LIKE 'DH\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'DROP PROPERTY GRAPH ' || g.graph_name;
  END LOOP;
  FOR o IN (SELECT object_name, object_type FROM user_objects
            WHERE (object_name LIKE 'DH\_%' ESCAPE '\' OR object_name LIKE 'AGENT\_%' ESCAPE '\')
            AND object_type IN ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'VIEW')) LOOP
    EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' ' || o.object_name;
  END LOOP;
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name IN
             ('DH_WORK_ORDERS', 'DH_ANOMALIES', 'DH_TELEMETRY', 'DH_MAINTENANCE', 'DH_SIM_STATE',
              'DH_PIPES', 'DH_METRICS', 'DH_ASSETS', 'DH_CONFIG', 'DH_JOB_LOG', 'DH_TEST_RESULTS')
            ORDER BY DECODE(table_name, 'DH_WORK_ORDERS', 1, 'DH_ANOMALIES', 2, 'DH_TELEMETRY', 3,
                            'DH_MAINTENANCE', 4, 'DH_SIM_STATE', 5, 'DH_PIPES', 6, 7)) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' PURGE';
  END LOOP;
END;
/
-- the context needs DROP ANY CONTEXT; ask ADMIN: DROP CONTEXT dh_ctx;
