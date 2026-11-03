-- =============================================================================
-- demo_state.sql - puts the demo into a defined state, so that every act can
--                  be shown, rehearsed or recorded on its own
--
-- Author:      Karin Patenge
-- Last update: 2026-10-30
--
-- Run as the demo user (OGBEMEA2026) from the scripts folder in SQLcl:
--
--   @sql/demo_state.sql base       Act 0 and the morning briefing   (about 1-2 min)
--   @sql/demo_state.sql incident   PS-04 tripped: Acts 1 to 5      (about 3-4 min)
--   @sql/demo_state.sql bypass     incident + BYP-1 open: Act 5 end (about 5-6 min)
--
-- Without an argument (or with an unknown one): base.
--
-- Every run starts from scratch, so it can be repeated as often as needed:
--   - stops DH_TICK_JOB (waits for a running tick), clears a what-if scenario
--   - removes what the acts leave behind: work orders of the agent, the open
--     bypass, live readings, anomalies, the simulation state, and the function
--     AGENT_CRITICAL_CUSTOMERS written by the coding agent (Act 5b)
--   - new 7-day history up to now, job started again
--   - incident / bypass: trips PS-04 (and opens BYP-1) and waits until the
--     network has reacted (the simulation runs in real time, every 30 s)
-- Expected cold buildings (both cities): base 5, incident 45, bypass 25.
--
-- Do not run it between the acts of the live session: it resets the history.
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET VERIFY OFF
SET DEFINE ON
SET LINESIZE 200
WHENEVER SQLERROR CONTINUE

-- Optional argument: define 1 as empty if it was not given
COLUMN 1 NEW_VALUE 1 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
COLUMN 1 CLEAR

COLUMN t_state NEW_VALUE t_state NOPRINT
SELECT CASE WHEN LOWER('&1') IN ('base', 'incident', 'bypass') THEN LOWER('&1') ELSE 'base' END AS t_state
FROM   dual;

PROMPT
PROMPT == demo_state.sql: &t_state
PROMPT == 1. Stop the job, clean up, new 7-day history
@@stop_tick_job.sql
EXEC dh_whatif.clear
DROP FUNCTION IF EXISTS agent_critical_customers;
EXEC dh_sim.reset_state
EXEC dh_sim.backfill
EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')
EXEC dh_job_tick

PROMPT == 2. Bring the network into the state and wait until it has reacted
DECLARE
  c_state  CONSTANT VARCHAR2(10) := '&t_state';
  l_cold   PLS_INTEGER;
  l_pump   VARCHAR2(20);

  PROCEDURE read_state IS
  BEGIN
    SELECT COUNT(*) INTO l_cold
    FROM   dh_assets WHERE asset_type = 'BUILDING' AND health_status = 'ALARM';
    SELECT MAX(pump_state) INTO l_pump FROM dh_sim_state WHERE asset_id = 'PS-04';
  END read_state;

  -- waits until the condition for p_target is met, at most p_max_s seconds
  PROCEDURE wait_for (p_target IN VARCHAR2, p_max_s IN PLS_INTEGER) IS
    l_ok BOOLEAN := FALSE;
  BEGIN
    FOR i IN 0 .. p_max_s / 10 LOOP
      read_state;
      l_ok := CASE p_target
                WHEN 'base'     THEN l_cold >= 5 AND l_pump = 'RUNNING'
                WHEN 'incident' THEN l_cold >= 45 AND l_pump = 'STOPPED'
                WHEN 'bypass'   THEN l_cold BETWEEN 1 AND 25
              END;
      EXIT WHEN l_ok;
      DBMS_SESSION.SLEEP(10);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_target, 9) || CASE WHEN l_ok THEN 'reached' ELSE 'NOT reached after ' || p_max_s || ' s' END
                         || ': ' || l_cold || ' cold buildings, PS-04 ' || NVL(l_pump, '-'));
  END wait_for;
BEGIN
  wait_for('base', 180);
  IF c_state IN ('incident', 'bypass') THEN
    dh_device_sim.trip('PS-04');
    wait_for('incident', 300);
  END IF;
  IF c_state = 'bypass' THEN
    dh_set_valve('BYP-1', 'OPEN');
    wait_for('bypass', 240);
  END IF;
END;
/

PROMPT == 3. Result
SELECT dh_device_sim.status AS status FROM dual;
SELECT district, COUNT(*) AS cold_buildings, SUM(apartments) AS apartments
FROM   dh_assets
WHERE  asset_type = 'BUILDING' AND health_status = 'ALARM'
GROUP  BY district
ORDER  BY district;
PROMPT Expected cold buildings: base 5 (VIE Ottakring, BUC Militari), incident 45, bypass 25.

UNDEFINE t_state
SET FEEDBACK ON
