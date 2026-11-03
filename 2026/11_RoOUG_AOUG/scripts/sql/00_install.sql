-- =============================================================================
-- 00_install.sql - installs the demo into the demo schema (run as that user with SQLcl)
--
-- Author:      Karin Patenge
-- Last update: 2026-10-28
--
--   sql -cloudconfig Wallet_<db>.zip ogbemea2026@<db>_high @00_install.sql vie
--   sql -cloudconfig Wallet_<db>.zip ogbemea2026@<db>_high @00_install.sql buc
--
-- Argument 1: city of the network in lower case (vie = Vienna, buc = Bucharest)
-- Prompts (from 01_schema.sql): IoT domain short ID, device password (hidden),
-- publish Y/N. Press Enter to keep the current value or to set them later.
--
-- Idempotent: safe to re-run. Tables are created only if missing, code objects
-- and graphs are replaced, the network is merged (twin OCIDs are kept), the
-- 7-day history is regenerated up to now, the job is created only once and
-- keeps its enabled/disabled state. Re-running with the other city switches
-- the district names (asset ids stay the same).
-- =============================================================================
-- Substitution on: a previous run in the same session may have turned it off
SET DEFINE ON
SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR CONTINUE

DEFINE city = '&1'

PROMPT == 01 schema
@@01_schema.sql
PROMPT == 02 network (&city)
@@02_network_&city..sql
-- The network script turns substitution off for its data; turn it on again
SET DEFINE ON
PROMPT == 03 backfill package
@@03_backfill.sql
PROMPT == 04 property graphs
@@04_property_graphs.sql
PROMPT == 05 analytics
@@05_analytics.sql
PROMPT == 06 IoT sync
@@06_iot_sync.sql
PROMPT == 06b device simulation
@@06b_device_sim.sql
PROMPT == 07 agent API
@@07_agent_api.sql
PROMPT == 08 jobs
@@08_jobs.sql
PROMPT == 09 APEX support
@@09_apex_support.sql

PROMPT == 7 days of history, first simulation step, first analysis
EXEC dh_sim.reset_state
EXEC dh_sim.backfill
EXEC dh_device_sim.tick
EXEC dh_analytics.run

PROMPT == invalid objects (should be none)
SELECT object_name, object_type FROM user_objects WHERE status = 'INVALID';

PROMPT == health overview
SELECT asset_type, health_status, COUNT(*) FROM dh_assets GROUP BY asset_type, health_status ORDER BY 1, 2;

PROMPT == simulation and job (the job is created disabled)
SELECT dh_device_sim.status AS simulation FROM dual;
SELECT name, value FROM dh_config WHERE name IN ('INGEST_MODE', 'SIM_ENABLED', 'IOT_PUBLISH') ORDER BY name;
SELECT job_name, enabled, repeat_interval FROM user_scheduler_jobs WHERE job_name = 'DH_TICK_JOB';
