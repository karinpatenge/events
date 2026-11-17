-- =============================================================================
-- stop_tick_job.sql - disables DH_TICK_JOB and waits until a running tick ends
--
-- Author:      Karin Patenge
-- Last update: 2026-11-14
--
-- Run as the demo user (GRAPHAI) from the scripts folder in SQLcl:
--   @sql/stop_tick_job.sql
--
-- A plain DBMS_SCHEDULER.DISABLE fails with ORA-27478 while the job is running.
-- force => TRUE disables the job and lets the current run finish; the loop then
-- waits (up to 120 seconds) until that run is over. A run that is still going
-- after that hangs (for example waiting for a lock): it is stopped with
-- DBMS_SCHEDULER.STOP_JOB. Safe to run again: an already disabled job is fine,
-- a missing job (before the first install) too.
-- =============================================================================
DECLARE
  e_no_job EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_no_job, -27476);   -- job does not exist
  l_n PLS_INTEGER := 0;
BEGIN
  BEGIN
    DBMS_SCHEDULER.DISABLE('DH_TICK_JOB', force => TRUE);
  EXCEPTION
    WHEN e_no_job THEN RETURN;
  END;
  FOR i IN 1 .. 120 LOOP
    SELECT COUNT(*) INTO l_n FROM user_scheduler_running_jobs WHERE job_name = 'DH_TICK_JOB';
    EXIT WHEN l_n = 0;
    DBMS_SESSION.SLEEP(1);
  END LOOP;
  IF l_n > 0 THEN
    DBMS_SCHEDULER.STOP_JOB('DH_TICK_JOB');                -- end the hanging run
    FOR i IN 1 .. 30 LOOP
      SELECT COUNT(*) INTO l_n FROM user_scheduler_running_jobs WHERE job_name = 'DH_TICK_JOB';
      EXIT WHEN l_n = 0;
      DBMS_SESSION.SLEEP(1);
    END LOOP;
    IF l_n > 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'DH_TICK_JOB still running after STOP_JOB - run stop_tick_job.sql again');
    END IF;
  END IF;
END;
/
