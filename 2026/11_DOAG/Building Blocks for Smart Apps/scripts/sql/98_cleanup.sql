--------------------------------------------------------------------------------
-- File       : 98_cleanup.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Removes all database objects of the demo user: jobs,
--              property graphs, views, RDF network with graphs, SODA
--              collections, Oracle Text preferences and stoplists, ONNX models,
--              tables, code objects and spatial metadata. The user remains.
--              Also covers objects that later demo scripts create.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as the demo user
--                sql doag2026@<tns_alias> @98_cleanup.sql
-- Caution    : Drops permanently (PURGE). Rebuild afterwards with 01_run_all.sql.
-- Log        : logs/sql/98_cleanup.log in the project folder,
--              overwritten on every run
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/98_cleanup.log

-- Must match the name in 00_create_user.sql
DEFINE demo_user = DOAG2026

-- RDF network: on Autonomous AI Database only the default network RDF_NETWORK
DEFINE network_owner = &demo_user
DEFINE network_name  = RDF_NETWORK

PROMPT
PROMPT === 98 Remove all objects of &demo_user ===

-- Safeguard: only in the demo schema, never as ADMIN
BEGIN
  IF USER <> UPPER('&demo_user') THEN
    RAISE_APPLICATION_ERROR(-20001, 'Connected as ' || USER || '. This script only runs as '
                                    || UPPER('&demo_user') || '.');
  END IF;
END;
/

ACCEPT confirm CHAR PROMPT 'Permanently drop all objects in schema &demo_user? Type YES to confirm: '

BEGIN
  IF UPPER('&confirm') <> 'YES' THEN
    RAISE_APPLICATION_ERROR(-20002, 'Cancelled, nothing was dropped.');
  END IF;
END;
/

DECLARE
  -- Variables before the nested procedure (PL/SQL requires declarations first)
  l_cnt    PLS_INTEGER;
  l_status NUMBER;

  PROCEDURE run(p_sql IN VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    DBMS_OUTPUT.PUT_LINE('OK      ' || p_sql);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('WARNING ' || p_sql || ' -> ' || SQLERRM);
  END run;
BEGIN
  -- 1. Scheduler jobs (e.g. time-lapse replay of the stream)
  FOR j IN (SELECT job_name FROM user_scheduler_jobs) LOOP
    BEGIN
      DBMS_SCHEDULER.DROP_JOB(j.job_name, force => TRUE);
      DBMS_OUTPUT.PUT_LINE('OK      Job ' || j.job_name);
    EXCEPTION
      WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('WARNING Job ' || j.job_name || ' -> ' || SQLERRM);
    END;
  END LOOP;

  -- 2. RDF network RDF_NETWORK with graphs KNEE_KG and FMA, entailment
  --    KNEE_KG_RIX, graph collection KNEE_FMA_VM, rulebase KNEE_RB and
  --    RDF text index. Before the views, because the graph views
  --    (RDF_NETWORK#RDFT_...) belong to the network.
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = '&network_name.#RDF_VALUE$';
  IF l_cnt > 0 THEN
    BEGIN
      SEM_APIS.DROP_RDF_NETWORK(cascade => TRUE, network_owner => '&network_owner', network_name => '&network_name');
      DBMS_OUTPUT.PUT_LINE('OK      RDF network &network_name');
    EXCEPTION
      WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('WARNING RDF network &network_name -> ' || SQLERRM);
    END;
  END IF;

  -- 3. SQL property graphs (before the tables they are based on)
  FOR g IN (SELECT graph_name FROM user_property_graphs) LOOP
    run('DROP PROPERTY GRAPH "' || g.graph_name || '"');
  END LOOP;

  -- 4. Views, including JSON Relational Duality Views. The DM$V... views of
  --    an embedding model are dropped with the model (step 8).
  FOR v IN (SELECT view_name FROM user_views WHERE view_name NOT LIKE 'DM$%') LOOP
    run('DROP VIEW IF EXISTS "' || v.view_name || '"');
  END LOOP;

  -- 5. Materialized Views
  FOR m IN (SELECT mview_name FROM user_mviews) LOOP
    run('DROP MATERIALIZED VIEW "' || m.mview_name || '"');
  END LOOP;

  -- 6. SODA collections (not via DROP TABLE, otherwise metadata is left behind)
  FOR c IN (SELECT uri_name FROM user_soda_collections) LOOP
    BEGIN
      l_status := DBMS_SODA.DROP_COLLECTION(c.uri_name);
      DBMS_OUTPUT.PUT_LINE('OK      SODA collection ' || c.uri_name);
    EXCEPTION
      WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('WARNING SODA collection ' || c.uri_name || ' -> ' || SQLERRM);
    END;
  END LOOP;

  -- 7. Oracle Text preferences and stoplists (e.g. German lexer from 06)
  FOR p IN (SELECT pre_name FROM ctx_user_preferences) LOOP
    BEGIN
      CTX_DDL.DROP_PREFERENCE(p.pre_name);
      DBMS_OUTPUT.PUT_LINE('OK      Text preference ' || p.pre_name);
    EXCEPTION
      WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('WARNING Text preference ' || p.pre_name || ' -> ' || SQLERRM);
    END;
  END LOOP;

  FOR s IN (SELECT spl_name FROM ctx_user_stoplists) LOOP
    BEGIN
      CTX_DDL.DROP_STOPLIST(s.spl_name);
      DBMS_OUTPUT.PUT_LINE('OK      Text stoplist ' || s.spl_name);
    EXCEPTION
      WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('WARNING Text stoplist ' || s.spl_name || ' -> ' || SQLERRM);
    END;
  END LOOP;

  -- 8. Models (ONNX embedding models for vector search)
  FOR m IN (SELECT model_name FROM user_mining_models) LOOP
    BEGIN
      DBMS_DATA_MINING.DROP_MODEL(m.model_name, force => TRUE);
      DBMS_OUTPUT.PUT_LINE('OK      Model ' || m.model_name);
    EXCEPTION
      WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('WARNING Model ' || m.model_name || ' -> ' || SQLERRM);
    END;
  END LOOP;

  -- 8a. Ubiquitous Database Search index from 11d_hybrid_search.sqlnb
  --     (drop with DBMS_SEARCH, not with DROP TABLE)
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'DOAG_SEARCH_IDX';
  IF l_cnt > 0 THEN
    BEGIN
      DBMS_SEARCH.DROP_INDEX('DOAG_SEARCH_IDX');
      DBMS_OUTPUT.PUT_LINE('OK      Search index DOAG_SEARCH_IDX');
    EXCEPTION
      WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('WARNING Search index DOAG_SEARCH_IDX -> ' || SQLERRM);
    END;
  END IF;

  -- 9. Tables. Dependent tables (e.g. DR$ tables of a text index)
  --    disappear with their base table, hence IF EXISTS.
  FOR t IN (SELECT table_name
            FROM   user_tables
            WHERE  nested = 'NO' AND secondary = 'N' AND iot_name IS NULL
            ORDER  BY CASE WHEN table_name LIKE 'DR$%' THEN 2 ELSE 1 END, table_name) LOOP
    run('DROP TABLE IF EXISTS "' || t.table_name || '" CASCADE CONSTRAINTS PURGE');
  END LOOP;

  -- 10. Code objects, triggers, sequences, synonyms, types, domains
  FOR o IN (SELECT object_type, object_name
            FROM   user_objects
            WHERE  object_type IN ('TRIGGER', 'PACKAGE', 'PROCEDURE', 'FUNCTION', 'SEQUENCE',
                                   'SYNONYM', 'TYPE', 'DOMAIN', 'MLE MODULE', 'MLE ENV')
            AND    object_name NOT LIKE 'BIN$%'
            -- GeoRaster DDL triggers of Oracle Spatial: system-managed, they stay
            AND    object_name NOT IN ('SDO_GEOR_BDDL_TRIGGER', 'SDO_GEOR_ADDL_TRIGGER')
            ORDER  BY DECODE(object_type, 'TRIGGER', 0, 'TYPE', 2, 1), object_name) LOOP
    run('DROP ' || o.object_type || ' IF EXISTS "' || o.object_name || '"'
        || CASE WHEN o.object_type = 'TYPE' THEN ' FORCE' END);
  END LOOP;

  -- 11. Spatial metadata
  DELETE FROM user_sdo_geom_metadata;
  DBMS_OUTPUT.PUT_LINE('OK      USER_SDO_GEOM_METADATA: ' || SQL%ROWCOUNT || ' entries');
  COMMIT;
END;
/

PURGE RECYCLEBIN;

PROMPT
PROMPT --- Remaining objects (should be empty; the GeoRaster DDL triggers of Oracle Spatial stay)
SELECT object_type, COUNT(*) AS cnt
FROM   user_objects
WHERE  object_name NOT LIKE 'BIN$%'
AND    object_name NOT IN ('SDO_GEOR_BDDL_TRIGGER', 'SDO_GEOR_ADDL_TRIGGER')
GROUP  BY object_type
ORDER  BY object_type;

PROMPT
PROMPT Done. Rebuild with 01_run_all.sql,
PROMPT or drop the user itself with 99_drop_user.sql (as ADMIN).

SPOOL OFF
