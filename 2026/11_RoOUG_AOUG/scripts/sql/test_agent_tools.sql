-- =============================================================================
-- test_agent_tools.sql - calls every AGENT_* tool once, as the agent would
--
-- Author:      Karin Patenge
-- Last update: 2026-10-27
--
-- Run as OGBEMEA2026 from the scripts folder, best after the PS-04 trip:
--   SPOOL logs/test_agent_tools.log
--   @sql/test_agent_tools.sql
--   SPOOL OFF
-- Every call must return JSON; an "error" key or an ORA- message is a failure.
-- Read-only, except tool 10: it creates one test work order and deletes it again.
-- =============================================================================
SET LONG 200000
SET LONGCHUNKSIZE 200000
SET PAGESIZE 0
SET LINESIZE 200

PROMPT == 1 agent_network_status
SELECT JSON_SERIALIZE(agent_network_status() RETURNING CLOB PRETTY) FROM dual;

PROMPT == 2 agent_active_anomalies('WARNING')
SELECT JSON_SERIALIZE(agent_active_anomalies('WARNING') RETURNING CLOB PRETTY) FROM dual;

PROMPT == 3 agent_find_root_cause
SELECT JSON_SERIALIZE(agent_find_root_cause() RETURNING CLOB PRETTY) FROM dual;

PROMPT == 3b agent_find_root_cause('Rahova')   (Bucharest: Rahova)
SELECT JSON_SERIALIZE(agent_find_root_cause('Rahova') RETURNING CLOB PRETTY) FROM dual;

PROMPT == 4 agent_impact_analysis('PS-04')
SELECT JSON_SERIALIZE(agent_impact_analysis('PS-04') RETURNING CLOB PRETTY) FROM dual;

PROMPT == 5 agent_what_if('PS-04', 'BYP-1')
SELECT JSON_SERIALIZE(agent_what_if('PS-04', 'BYP-1') RETURNING CLOB PRETTY) FROM dual;

PROMPT == 6 agent_predict_failures(240)
SELECT JSON_SERIALIZE(agent_predict_failures(240) RETURNING CLOB PRETTY) FROM dual;

PROMPT == 7 agent_critical_assets(5)
SELECT JSON_SERIALIZE(agent_critical_assets(5) RETURNING CLOB PRETTY) FROM dual;

PROMPT == 8 agent_asset_details('PS-04')
SELECT JSON_SERIALIZE(agent_asset_details('PS-04') RETURNING CLOB PRETTY) FROM dual;

PROMPT == 9 agent_maintenance_history('PS-04')
SELECT JSON_SERIALIZE(agent_maintenance_history('PS-04') RETURNING CLOB PRETTY) FROM dual;

PROMPT == 10 agent_create_work_order (test, deleted again)
SELECT JSON_SERIALIZE(agent_create_work_order('PS-04', 'P1', 'TEST work order from test_agent_tools.sql') RETURNING CLOB PRETTY) FROM dual;
DELETE FROM dh_work_orders WHERE title = 'TEST work order from test_agent_tools.sql';
COMMIT;

SET PAGESIZE 100
PROMPT == Invalid objects (should be none)
SELECT object_name, object_type FROM user_objects WHERE status = 'INVALID';
