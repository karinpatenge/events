-- =============================================================================
-- demo_act3_graph_algorithms.sql   (Act 3: graph algorithms in the database)
--
-- Author:      Karin Patenge
-- Last update: 2026-11-16
--
-- DBMS_OGA graph algorithm functions return a graph with new properties;
-- GRAPH_TABLE reads them like any other property. Nothing leaves the database.
-- Fallbacks without DBMS_OGA are marked "SQL/PGQ only".
-- Runs as a whole (@sql/demo_act3_graph_algorithms.sql) or statement by statement.
-- The graph owner in the JSON arguments of steps 2b and 6 is written out as
-- GRAPHAI. Run the script as that user, or replace GRAPHAI there with
-- your schema name. Step 2a builds its JSON with USER and fits any schema.
-- Starting state: incident with BYP-1 closed (@sql/demo_state.sql incident).
-- The what-if scenario (steps 3 and 4) lives only in this session; if you stop
-- before the end, run EXEC dh_whatif.clear yourself.
-- =============================================================================

-- 1) Criticality: PageRank on the dependency graph (edges point upstream).
--    The more (and the more important) assets depend on you, the higher your rank.
SELECT asset_id, asset_type, ROUND(rank, 4) AS pagerank
FROM   GRAPH_TABLE (
          DBMS_OGA.PAGERANK(
            dh_dependency,
            PROPERTY(VERTEX OUTPUT rank),
            100, 1e-6, 0.85d, FALSE)
          MATCH (v IS asset WHERE v.asset_type IN ('PUMP_STATION', 'SUBSTATION'))
          COLUMNS (v.asset_id, v.asset_type, v.rank))
ORDER  BY rank DESC
FETCH  FIRST 10 ROWS ONLY;

-- 1b) SQL/PGQ only: number of buildings that depend on each pump station
SELECT s_id, COUNT(DISTINCT b_id) AS dependent_buildings, SUM(apts) AS apartments
FROM   GRAPH_TABLE (
          dh_network
          MATCH (s IS asset WHERE s.asset_type = 'PUMP_STATION')
                -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
                (b IS asset WHERE b.asset_type = 'BUILDING')
          COLUMNS (s.asset_id AS s_id, b.asset_id AS b_id, b.apartments AS apts))
GROUP  BY s_id
ORDER  BY dependent_buildings DESC;

-- 2) Root cause, algorithmic: Personalized PageRank from the symptoms.
--    Step a: the seeds = substations that feed cold buildings, as vertex ids
--    A vertex id has four parts: graph owner, graph name, element table and key.
--    ELEM_TABLE is the vertex table of the graph, not a filter: DH_DEPENDENCY is
--    defined on the view DH_ASSETS_LIVE_V (04_property_graphs.sql), so its
--    vertices come from there. With DH_ASSETS the algorithm finds none of the
--    seeds. The GRAPH_TABLE subquery decides which substations are seeds.
SELECT JSON_ARRAYAGG(
          JSON_OBJECT('GRAPH_OWNER' VALUE USER, 'GRAPH_NAME' VALUE 'DH_DEPENDENCY',
                      'ELEM_TABLE' VALUE 'DH_ASSETS_LIVE_V',
                      'KEY_VALUE' VALUE JSON_OBJECT('ASSET_ID' VALUE ss_id))) AS seeds
FROM  (SELECT DISTINCT ss_id
       FROM GRAPH_TABLE (
              dh_dependency
                MATCH (b IS asset WHERE b.asset_type = 'BUILDING' AND b.health_status = 'ALARM')
                      -[IS depends_on]-> (ss IS asset)
                COLUMNS (ss.asset_id AS ss_id)));

--    Step b: paste the array from step a into JSON('...') - or use the agent tool below
SELECT asset_id, asset_type, ROUND(rank, 4) AS score
FROM   GRAPH_TABLE (
          DBMS_OGA.PERSONALIZED_PAGERANK_SET(
            dh_dependency, PROPERTY(VERTEX OUTPUT rank),
            JSON('[{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_DEPENDENCY","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"SS-09.3"}},{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_DEPENDENCY","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"SS-04.1"}},{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_DEPENDENCY","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"SS-04.2"}},{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_DEPENDENCY","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"SS-04.4"}},{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_DEPENDENCY","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"SS-05.1"}},{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_DEPENDENCY","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"SS-05.3"}},{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_DEPENDENCY","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"SS-05.4"}},{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_DEPENDENCY","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"SS-05.2"}},{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_DEPENDENCY","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"SS-04.3"}}]'),
            100, 1e-6, 0.85d, FALSE)
          MATCH (v IS asset WHERE v.asset_type IN ('PUMP_STATION', 'SUBSTATION'))   -- plants feed everything
          COLUMNS (v.asset_id, v.asset_type, v.rank))
WHERE  rank > 0                                    -- not reachable from the seeds
ORDER  BY rank DESC
FETCH  FIRST 5 ROWS ONLY;

SELECT JSON_QUERY(agent_find_root_cause(), '$.personalized_pagerank_top5' RETURNING CLOB PRETTY) AS ppr FROM dual;

-- 3) What if PS-04 stays down? Weakly connected components on the live graph.
--    The live graph is built on views; the scenario is a session context.
--
--    How the what-if works (04_property_graphs.sql):
--    - dh_whatif.set_scenario writes the scenario into the context DH_CTX of
--      this session: assets out of service (OOS), valves opened (OPEN_VALVES).
--    - DH_LIVE_NETWORK is a property graph on two views that read DH_CTX:
--      DH_ASSETS_LIVE_V  assets in service and not in OOS, here without PS-04
--      DH_PIPES_LIVE_V   open pipes plus the valves of the scenario, and only
--                        pipes between assets that are still there
--    - Nothing is changed or copied: the tables, the job, APEX and the agent
--      see the real network. The scenario ends with dh_whatif.clear or the session.
--
--    The query:
--    - DBMS_OGA.WCC computes the weakly connected components: groups of assets
--      connected by pipes, in either direction. It returns the graph with a
--      new vertex property COMP (the component id), read in COLUMNS like any
--      other property.
--    - Per component: number of assets, of buildings, and its heat plant.
--      A component without a plant (PLANT is NULL) is an island: no heat can
--      reach it. NULLS FIRST lists the islands on top.
--    Expected (BYP-1 closed): 5 islands with 40 buildings in all, PS-05 with
--    its substations (25 assets, 20 buildings) and the 4 substations of PS-04
--    (6 assets, 5 buildings each), then HP-A (76 assets, 60 buildings) and
--    HP-B (126 assets, 100 buildings).
EXEC dh_whatif.set_scenario(p_out_of_service => 'PS-04');

SELECT comp, COUNT(*) AS assets,
       SUM(CASE WHEN asset_type = 'BUILDING' THEN 1 ELSE 0 END)  AS buildings,
       MAX(CASE WHEN asset_type = 'PLANT' THEN asset_id END)     AS plant
FROM   GRAPH_TABLE (
  DBMS_OGA.WCC(
    dh_live_network,
    PROPERTY(VERTEX OUTPUT comp))
         MATCH (a IS asset)
         COLUMNS (a.asset_id, a.asset_type, a.comp))
GROUP  BY comp
ORDER  BY plant NULLS FIRST, buildings DESC;

-- 3b) SQL/PGQ only: buildings that no plant can reach in this scenario
--    The same question without DBMS_OGA, and in flow direction: the graph
--    query lists every building 1 to 5 pipes downstream of a heat plant in
--    the live graph (plant -> pump station -> pump station -> substation ->
--    building is 4 pipes). NOT IN keeps the buildings that no plant reaches.
--    Expected: 40 buildings, 2,796 apartments (the 40 buildings of query 3).
SELECT COUNT(*) AS buildings_without_supply, SUM(apartments) AS apartments
FROM   dh_assets b
WHERE  b.asset_type = 'BUILDING'
AND    b.asset_id NOT IN (
  SELECT x_id
  FROM GRAPH_TABLE (
          dh_live_network
          MATCH (pl IS asset WHERE pl.asset_type = 'PLANT') -[IS supplies]->{1,5}
                (x IS asset WHERE x.asset_type = 'BUILDING')
          COLUMNS (x.asset_id AS x_id)));

-- 4) ... and if we open bypass valve BYP-1 (PS-06 -> PS-05)?
--    Same two queries as 3 and 3b: Gleisshammer (hospital, nursing home) is back,
--    Galgenhof still cut off (20 buildings instead of 40)
EXEC dh_whatif.set_scenario(p_out_of_service => 'PS-04', p_open_valves => 'BYP-1');

SELECT comp, COUNT(*) AS assets,
       SUM(CASE WHEN asset_type = 'BUILDING' THEN 1 ELSE 0 END)  AS buildings,
       MAX(CASE WHEN asset_type = 'PLANT' THEN asset_id END)     AS plant
FROM   GRAPH_TABLE (
          DBMS_OGA.WCC(
            dh_live_network,
            PROPERTY(VERTEX OUTPUT comp))
          MATCH (a IS asset)
          COLUMNS (a.asset_id, a.asset_type, a.comp))
GROUP  BY comp
ORDER  BY plant NULLS FIRST, buildings DESC;

SELECT COUNT(*) AS buildings_without_supply, SUM(apartments) AS apartments
FROM   dh_assets b
WHERE  b.asset_type = 'BUILDING'
AND    b.asset_id NOT IN (
  SELECT x_id
  FROM GRAPH_TABLE (
          dh_live_network
          MATCH (pl IS asset WHERE pl.asset_type = 'PLANT') -[IS supplies]->{1,5}
                (x IS asset WHERE x.asset_type = 'BUILDING')
          COLUMNS (x.asset_id AS x_id)));

-- Back to the real network (the scenario only lives in this session)
EXEC dh_whatif.clear;

-- 5) The same as one agent tool
SELECT JSON_SERIALIZE(agent_impact_analysis('PS-04') RETURNING CLOB PRETTY) AS impact FROM dual;

-- 6) Bonus: network distance from heat plant A (Bellman-Ford, weight = pipe length).
--    Pump stations fed by plant B are not reachable from A (distance infinite) and left out.
SELECT asset_id, asset_type, CAST(ROUND(dist) AS NUMBER) AS metres_from_plant
FROM   GRAPH_TABLE (
  DBMS_OGA.BELLMAN_FORD(
                      dh_live_network,
                      JSON('{"GRAPH_OWNER":"GRAPHAI","GRAPH_NAME":"DH_LIVE_NETWORK","ELEM_TABLE":"DH_ASSETS_LIVE_V","KEY_VALUE":{"ASSET_ID":"HP-A"}}'),
                      PROPERTY(EDGE INPUT length_m DEFAULT ON NULL 0),
                      PROPERTY(VERTEX OUTPUT dist))
         MATCH (v IS asset WHERE v.asset_type = 'PUMP_STATION')
         COLUMNS (v.asset_id, v.asset_type, v.dist))
WHERE  dist IS NOT INFINITE
ORDER  BY dist;
