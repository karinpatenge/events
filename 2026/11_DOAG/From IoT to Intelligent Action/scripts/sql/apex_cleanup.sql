-- =============================================================================
-- apex_cleanup.sql - ends all open work-order workflows and tasks in APEX
--
-- Author:      Karin Patenge
-- Last update: 2026-11-17
--
-- Run as the demo user (GRAPHAI) from the scripts folder in SQLcl:
--   @sql/apex_cleanup.sql
-- demo_state.sql, 00c_install_all.sql and test_all.sql call it before their
-- reset, 99_teardown.sql before it drops the tables.
--
-- A reset (demo_state.sql) deletes the work orders created during the demo,
-- but not the APEX workflows and tasks that belong to them. A task whose work
-- order is gone can no longer be completed or cancelled: APEX fails with
-- "System of record(s) associated with this task instance is not found".
-- So this script ends them while their work orders still exist:
--   1. terminates the open work-order workflows (active, suspended, faulted)
--   2. cancels the open tasks (terminating a workflow leaves its open task
--      behind; terminating first keeps a cancelled task from moving its
--      workflow on to the next step)
--   3. deletes the open tasks that cannot be cancelled because their work
--      order is already gone (APEX needs the row to cancel a task)
-- It does not read the demo tables, so it also works after a teardown.
-- It ends every open work order flow in the app, including ones you are still
-- working on: run it only when the demo is reset anyway.
--
-- The app is found through its work-order workflows (static ID work-order),
-- so the application ID does not matter. Each app is handled in an APEX
-- session of the user who started its last workflow (the business
-- administrator of the tasks); the session is detached at the end, otherwise
-- a later "apex import" in the same SQLcl session fails with ORA-20987.
-- Safe to run again: what is already ended is skipped; without the app or
-- without workflows there is nothing to do.
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  l_wf      PLS_INTEGER := 0;
  l_tasks   PLS_INTEGER := 0;
  l_orphans PLS_INTEGER := 0;
  l_err     PLS_INTEGER := 0;
  l_n       PLS_INTEGER;
BEGIN
  FOR app IN (SELECT application_id,
                     MAX(initiator) KEEP (DENSE_RANK LAST ORDER BY start_time) AS initiator
              FROM   apex_workflows
              WHERE  workflow_def_static_id = 'work-order' AND initiator IS NOT NULL
              GROUP  BY application_id) LOOP
    apex_session.create_session(p_app_id => app.application_id, p_page_id => 1, p_username => app.initiator);

    -- 1. open workflows
    FOR r IN (SELECT workflow_id FROM apex_workflows
              WHERE  application_id = app.application_id
              AND    workflow_def_static_id = 'work-order'
              AND    state_code IN ('ACTIVE', 'SUSPENDED', 'FAULTED')) LOOP
      BEGIN
        apex_workflow.terminate(p_instance_id => r.workflow_id);
        l_wf := l_wf + 1;
      EXCEPTION
        WHEN OTHERS THEN
          l_err := l_err + 1;
          DBMS_OUTPUT.PUT_LINE('  workflow ' || r.workflow_id || ': ' || SQLERRM);
      END;
    END LOOP;

    -- 2. open tasks; one whose work order is gone fails here and stays open
    FOR r IN (SELECT task_id FROM apex_tasks
              WHERE  application_id = app.application_id
              AND    state_code IN ('UNASSIGNED', 'ASSIGNED')) LOOP
      BEGIN
        apex_human_task.cancel_task(p_task_id => r.task_id);
        l_tasks := l_tasks + 1;
      EXCEPTION
        WHEN OTHERS THEN NULL;                        -- handled in step 3
      END;
    END LOOP;

    -- 3. tasks still open after step 2 have no work order: they can only be
    --    deleted
    SELECT COUNT(*) INTO l_n FROM apex_tasks
    WHERE  application_id = app.application_id AND state_code IN ('UNASSIGNED', 'ASSIGNED');
    IF l_n > 0 THEN
      apex_human_task.delete_tasks(p_application_id         => app.application_id,
                                   p_states                 => apex_t_varchar2('UNASSIGNED', 'ASSIGNED'),
                                   p_include_workflow_tasks => TRUE);
      l_orphans := l_orphans + l_n;
    END IF;

    COMMIT;
    apex_session.detach;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('APEX cleanup: ' || l_wf || ' workflows terminated, ' || l_tasks || ' tasks cancelled, '
                       || l_orphans || ' tasks without work order deleted'
                       || CASE WHEN l_err > 0 THEN ', ' || l_err || ' failed (see above)' END);
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    BEGIN apex_session.detach; EXCEPTION WHEN OTHERS THEN NULL; END;
    DBMS_OUTPUT.PUT_LINE('APEX cleanup skipped: ' || SQLERRM);
END;
/
