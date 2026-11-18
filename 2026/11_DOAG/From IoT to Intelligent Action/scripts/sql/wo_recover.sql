-- =============================================================================
-- wo_recover.sql - gets a work order going again whose APEX workflow stopped
--                  between two steps
--
-- Author:      Karin Patenge
-- Last update: 2026-11-18
--
-- Run as the demo user (GRAPHAI) from the scripts folder in SQLcl:
--   @sql/wo_recover.sql <work order number>
--
-- Symptom: a task was completed on page 8, but the next task never appears
-- and the status of the work order stays (check_consistency.sql, check W8b).
-- APEX then shows the workflow as Active, its last step Completed, and no
-- step after it.
--
-- What it does:
--   - "Confirm work done" was completed: closes the work order as the
--     workflow would have (dh_wo_flow.close_work_order: status DONE, asset
--     repaired, maintenance entry) and terminates the workflow.
--   - stopped at an earlier step: terminates the workflow, cancels its open
--     task and sets the work order back to NEW without workflow, so that
--     page 6 offers "Start workflow" again.
-- A work order whose workflow is not stopped is left alone. Safe to run again.
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
DECLARE
  c_wo_id  CONSTANT NUMBER := &1;
  l_status dh_work_orders.status%TYPE;
  l_wf_id  dh_work_orders.workflow_id%TYPE;
  l_app    NUMBER;
  l_user   VARCHAR2(255);
  l_state  VARCHAR2(30);
  l_open   PLS_INTEGER;
  l_done   PLS_INTEGER;
BEGIN
  SELECT status, workflow_id INTO l_status, l_wf_id FROM dh_work_orders WHERE wo_id = c_wo_id;
  IF l_wf_id IS NULL THEN
    DBMS_OUTPUT.PUT_LINE('Work order ' || c_wo_id || ' (' || l_status || ') has no workflow: nothing to do');
    RETURN;
  END IF;

  SELECT MAX(application_id), MAX(initiator), MAX(state_code) INTO l_app, l_user, l_state
  FROM   apex_workflows WHERE workflow_id = l_wf_id;
  -- steps not completed yet (a waiting task, a running step) and the last task done
  SELECT COUNT(CASE WHEN state <> 'COMPLETED' THEN 1 END),
         COUNT(CASE WHEN static_id = 'confirm-work-done' AND state = 'COMPLETED' THEN 1 END)
  INTO   l_open, l_done
  FROM   apex_workflow_activities WHERE workflow_id = l_wf_id;

  IF l_state = 'ACTIVE' AND l_open > 0 THEN
    DBMS_OUTPUT.PUT_LINE('Work order ' || c_wo_id || ': the workflow is waiting at a step, not stopped: nothing to do');
    RETURN;
  END IF;

  IF l_app IS NOT NULL THEN
    apex_session.create_session(p_app_id => l_app, p_page_id => 1, p_username => l_user);
    IF l_state IN ('ACTIVE', 'SUSPENDED', 'FAULTED') THEN
      apex_workflow.terminate(p_instance_id => l_wf_id);
    END IF;
    FOR t IN (SELECT task_id FROM apex_tasks
              WHERE  application_id = l_app AND detail_pk = TO_CHAR(c_wo_id)
              AND    state_code IN ('UNASSIGNED', 'ASSIGNED')) LOOP
      apex_human_task.cancel_task(p_task_id => t.task_id);
    END LOOP;
  END IF;

  IF l_done > 0 THEN
    dh_wo_flow.close_work_order(c_wo_id);
    DBMS_OUTPUT.PUT_LINE('Work order ' || c_wo_id || ': closed, asset repaired, workflow terminated');
  ELSIF l_status IN ('NEW', 'PLANNED', 'IN_PROGRESS') THEN
    UPDATE dh_work_orders SET status = 'NEW', workflow_id = NULL WHERE wo_id = c_wo_id;
    DBMS_OUTPUT.PUT_LINE('Work order ' || c_wo_id || ': back to NEW; start its workflow again on page 6');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Work order ' || c_wo_id || ' is ' || l_status || '; workflow terminated');
  END IF;
  COMMIT;
  IF l_app IS NOT NULL THEN
    apex_session.detach;
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('Work order ' || c_wo_id || ' does not exist');
  WHEN OTHERS THEN
    ROLLBACK;
    BEGIN apex_session.detach; EXCEPTION WHEN OTHERS THEN NULL; END;
    DBMS_OUTPUT.PUT_LINE('Work order ' || c_wo_id || ': ' || SQLERRM);
END;
/
UNDEFINE 1
