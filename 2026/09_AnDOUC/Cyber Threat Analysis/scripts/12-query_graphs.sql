/*****************************************************
 *
 * Analyze the graphs using SQL/PGQ and DBMS_OGA
 *
 * File name: 12-query_graphs.sql
 * Author: Karin Patenge
 * Last updated: 2026-09-09
 *
 ****************************************************/

-------------------
-- Session settings
-------------------

ALTER SESSION FORCE PARALLEL QUERY PARALLEL 8;
ALTER SESSION ENABLE PARALLEL DML;

-----------------------------------------------
-- Graph Studio settings
-- Note:
--  Required only for notebooks in Graph Studio
-----------------------------------------------

DECLARE
    l_old_group VARCHAR2(30);
BEGIN
  DBMS_SESSION.SWITCH_CURRENT_CONSUMER_GROUP(
        new_consumer_group     => 'HIGH',
        old_consumer_group     => l_old_group,
        initial_group_on_error => TRUE
    );
END;
/

-- Enable parallelism for graph queries and graph algorithms
BEGIN
    EXECUTE IMMEDIATE 'ALTER SESSION FORCE PARALLEL QUERY PARALLEL 8';
    EXECUTE IMMEDIATE 'ALTER SESSION FORCE PARALLEL DML PARALLEL 8';
END;
/

-------------------------------------------
-- Graph queries for the ground-truth graph
-------------------------------------------

-- Show the ground-truth graph
SELECT *
FROM
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH (a) -[e]-> (b)
    COLUMNS (
      VERTEX_ID(a) AS src_node,
      EDGE_ID(e) AS edge,
      VERTEX_ID(b) AS dst_node
    )
  );

-- Show 2-hop ground-truth attack chains
SELECT *
FROM
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH (u IS user_domain) -[a IS authenticated]-> (src IS computer) -[c IS compromised]-> (dst IS computer)
    WHERE a.id = c.id
    COLUMNS (
      u.user_domain,
      src.computer AS staging_host,
      dst.computer AS victim_host,
      c.time AS compromise_time,
      VERTEX_ID(u) AS user_domain_vertex,
      EDGE_ID(a) AS authenticated_edge,
      VERTEX_ID(src) AS staging_host_vertex,
      EDGE_ID(c) AS compomised_edge,
      VERTEX_ID(dst) AS victim_host_vertex
    )
  );


-- Which users authenticated which staging hosts and when in the ground-truth graph?
SELECT *
FROM
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH (a IS user_domain) -[e IS authenticated]-> (b IS computer)
    COLUMNS (
      a.user_domain AS user_domain,
      b.computer AS staging_host,
      e.time AS auth_time,
      VERTEX_ID(a) AS src_node,
      EDGE_ID(e) AS edge,
      VERTEX_ID(b) AS dst_node
    )
  )
ORDER BY
  user_domain,
  staging_host,
  auth_time;

-- How many staging hosts did each user authenticate to in the ground-truth graph?
SELECT
  user_domain,
  COUNT(*) AS cnt
FROM
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH (a IS user_domain) -[e IS authenticated]-> (b IS computer)
    COLUMNS (
      a.user_domain AS user_domain,
      b.computer AS staging_host
    )
  )
GROUP BY
  user_domain
ORDER BY
  user_domain;

-- How many users authenticated to each staging host in the ground-truth graph?
SELECT
  staging_host,
  COUNT(*) AS cnt
FROM
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH (a IS user_domain) -[e IS authenticated]-> (b IS computer)
    COLUMNS (
      a.user_domain AS user_domain,
      b.computer AS staging_host
    )
  )
GROUP BY
  staging_host
ORDER BY
  staging_host;

-- Show hosts compromised via staging hosts 'C17693' and 'C22409' in the ground-truth graph
SELECT *
FROM
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH (u IS user_domain) -[a IS authenticated]-> (src IS computer) -[c IS compromised]-> (dst IS computer)
    WHERE a.id = c.id AND src.computer = 'C17693'
    COLUMNS (
      u.user_domain,
      src.computer AS staging_host,
      dst.computer AS victim_host,
      c.time AS compromise_time,
      VERTEX_ID(u) AS user_domain_vertex,
      EDGE_ID(a) AS authenticated_edge,
      VERTEX_ID(src) AS staging_host_vertex,
      EDGE_ID(c) AS compomised_edge,
      VERTEX_ID(dst) AS victim_host_vertex
    )
  );

SELECT *
FROM
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH (u IS user_domain) -[a IS authenticated]-> (src IS computer) -[c IS compromised]-> (dst IS computer)
    WHERE a.id = c.id AND src.computer = 'C22409'
    COLUMNS (
      u.user_domain,
      src.computer AS staging_host,
      dst.computer AS victim_host,
      c.time AS compromise_time,
      VERTEX_ID(u) AS user_domain_vertex,
      EDGE_ID(a) AS authenticated_edge,
      VERTEX_ID(src) AS staging_host_vertex,
      EDGE_ID(c) AS compomised_edge,
      VERTEX_ID(dst) AS victim_host_vertex
    )
  );

---------------------------------------------
-- Graph algorithms on the ground-truth graph
---------------------------------------------

-- Run PageRank for staging hosts (sources of compromise) to identify the most important ones
SELECT DISTINCT *
FROM
  GRAPH_TABLE (
    DBMS_OGA.PAGERANK (
      lanl_ground_truth_graph,
      PROPERTY (VERTEX OUTPUT rank),
      10, 1.0, 0.85d, FALSE
    )
    MATCH (src IS computer) -[e]-> (dst IS computer)
    COLUMNS (
      src.computer AS computer,
      src.rank AS rank
    )
  )
ORDER BY
  rank DESC
FETCH FIRST 10 ROWS ONLY;

-- Run PageRank for victim hosts (destinations of compromise):
SELECT DISTINCT *
FROM
  GRAPH_TABLE (
    DBMS_OGA.PAGERANK (
      lanl_ground_truth_graph,
      PROPERTY (VERTEX OUTPUT rank),
      10, 1.0, 0.85d, FALSE
    )
    MATCH (src IS computer) -[e]-> (dst IS computer)
    COLUMNS (
      dst.computer AS computer,
      dst.rank AS rank
    )
  )
ORDER BY
  rank DESC
FETCH FIRST 10 ROWS ONLY;

-- Run PageRank for all computers (both staging and victim hosts):
SELECT  *
FROM
  GRAPH_TABLE (
    DBMS_OGA.PAGERANK (
      lanl_ground_truth_graph,
      PROPERTY (VERTEX OUTPUT rank),
      10, 1.0, 0.85d, FALSE
    )
    MATCH (c IS computer)
    COLUMNS (
      c.computer AS computer,
      c.rank AS rank
    )
  )
ORDER BY
  rank DESC
FETCH FIRST 10 ROWS ONLY;

------------------------------------
-- Graph queries for the cyber graph
------------------------------------

-- Query suggested by Léo
SELECT *
FROM GRAPH_TABLE (
  lanl_cyber_graph
  MATCH
    (u IS user_domain) -[a IS auth_src_authenticated]-> (src IS computer),
    (u) -[b IS auth_dst_authenticated]-> (dst IS computer)
  WHERE
    a.id = b.id
    AND a.redteam = 1
  COLUMNS (
    VERTEX_ID(u)   AS u,
    VERTEX_ID(src) AS src,
    VERTEX_ID(dst) AS dst,
    EDGE_ID(a)     AS a,
    EDGE_ID(b)     AS b
  )
);

-- Evidence trail around one confirmed chain (network + process activity):
SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH
      (src IS computer) -[f IS flows_connected]-> (dst IS computer)
    WHERE
      src.computer = 'C17693'
      -- src.computer = :staging_host
      AND dst.computer = 'C11178'
      -- AND dst.computer = :victim_host
      -- AND f.time BETWEEN :compromise_time - :t AND :compromise_time + :t
      -- AND f.time BETWEEN 769373 - 1000 AND 769373 + 1000
    COLUMNS (
      src.computer AS src_computer,
      dst.computer AS dst_computer,
      f.protocol AS protocol,
      f.dst_port AS dst_port,
      f.packet_cnt AS packet_cnt,
      f.byte_cnt AS byte_cnt,
      f.time AS time,
      f.duration AS duration,
      VERTEX_ID(src) AS src_computer_vertex,
      EDGE_ID(f) AS flows_connected,
      VERTEX_ID(dst) AS dst_computer_vertex
    )
  )
ORDER BY
  packet_cnt DESC,
  byte_cnt DESC;
-- 310 rows

SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (c IS computer) -[r IS ran]-> (p IS process)
    WHERE
      -- c.computer = :victim_host
      c.computer IS NOT NULL
      -- AND r.time BETWEEN :compromise_time - :t AND :compromise_time + :t
      AND r.time BETWEEN 769373 - 1000 AND 769373 + 1000
    COLUMNS (
      c.computer AS src_computer,
      p.process AS process_name,
      r.time AS time,
      r.start_end AS start_end
    )
  );

-- Potentially compromised hosts:

-- AUTH data: Which other computers were connected from the staging host, that are not known to be compromised from the ground-truth graph?
SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (src IS computer) -[ac IS auth_connected]-> (dst IS computer)
    COLUMNS (
      src.computer AS staging_host,
    dst.computer AS candidate_victim,
    ac.time
  )
) c
WHERE
  candidate_victim NOT IN (
    SELECT DISTINCT victim_host
    FROM GRAPH_TABLE (
      lanl_ground_truth_graph
      MATCH (src IS computer) -[c IS compromised]-> (dst IS computer)
      COLUMNS (
        src.computer AS staging_host,
        dst.computer AS victim_host
      )
    )
  )
  AND staging_host IN (
    SELECT DISTINCT staging_host
    FROM
      GRAPH_TABLE (
        lanl_ground_truth_graph
        MATCH (src IS computer) -[c IS compromised] -> (dst IS computer)
        COLUMNS (
          src.computer AS staging_host
        )
      )
    );

-- FLOWS data: Which other computers were connected from the staging host, that are not known to be compromised from the ground-truth graph?
SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (src IS computer) -[ac IS flows_connected]-> (dst IS computer)
    COLUMNS (
      src.computer AS staging_host,
      dst.computer AS candidate_victim,
      ac.time
    )
  ) c
  WHERE
    c.candidate_victim NOT IN (
      SELECT DISTINCT victim_host
      FROM
        GRAPH_TABLE (
          lanl_ground_truth_graph
          MATCH (src IS computer) -[c IS compromised]-> (dst IS computer)
          COLUMNS (
            src.computer AS staging_host,
            dst.computer AS victim_host
          )
        )
      )
    AND c.staging_host IN (
      SELECT DISTINCT staging_host
      FROM GRAPH_TABLE (
        lanl_ground_truth_graph
        MATCH (src IS computer) -[c IS compromised] -> (dst IS computer)
        COLUMNS (
          src.computer AS staging_host
        )
      )
    );

-- Lookalike patterns:

-- Same user domain -> computer edges as in the ground-truth graph
SELECT
  c.user_domain AS user_domain,
  c.authenticated_computer AS authenticated_computer,
  c.auth_orientation AS auth_orientation,
  c.auth_type AS auth_type,
  c.auth_time AS auth_time,
  c.logon_type AS logon_type
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH
      (u1 IS user_domain) -[e1 IS auth_src_authenticated]-> (c1 IS computer)
    WHERE
       u1.user_domain = 'U293@DOM1'
       -- AND c1.computer = :authenticated_computer
       -- AND e1.auth_orientation = :auth_orientation
    COLUMNS (
      u1.user_domain AS user_domain,
      c1.computer AS authenticated_computer,
      e1.auth_orientation AS auth_orientation,
      e1.auth_type AS auth_type,
      e1.time AS auth_time,
      e1.logon_type AS logon_type
    )
  ) c,
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH
      (u2 IS user_domain) -[e2 IS authenticated]-> (c2 IS computer)
    COLUMNS (
      u2.user_domain AS user_domain,
      c2.computer AS authenticated_computer
    )
  ) gt
WHERE
  c.authenticated_computer = gt.authenticated_computer
  AND c.user_domain = gt.user_domain;

--
-- Checks on AUTH data
--
SELECT DISTINCT auth_orientation
FROM AUTH
WHERE auth_orientation IS NOT NULL;

SELECT DISTINCT logon_type
FROM AUTH
WHERE src_user_domain <> dst_user_domain
ORDER BY logon_type;

SELECT DISTINCT logon_type
FROM AUTH
WHERE src_user_domain = dst_user_domain
ORDER BY logon_type;

SELECT DISTINCT auth_orientation
FROM AUTH
WHERE src_user_domain <> dst_user_domain
ORDER BY auth_orientation;

SELECT DISTINCT auth_orientation
FROM AUTH
WHERE src_user_domain = dst_user_domain
ORDER BY auth_orientation;

SELECT *
FROM auth
WHERE src_user_domain = 'U293@DOM1' AND REDTEAM=1
ORDER BY time;

SELECT *
FROM auth
WHERE src_user_domain = 'U293@DOM1' AND src_computer = 'C882'
ORDER BY time;

SELECT auth_type, redteam, COUNT(*)
FROM auth
GROUP BY auth_type, redteam
ORDER BY redteam DESC, auth_type;

--
-- Enumerate ground-truth attack chains
--

SELECT *
FROM GRAPH_TABLE (
  lanl_ground_truth_graph
  MATCH (u IS user_domain) -[a IS authenticated]-> (src IS computer) -[c IS compromised]-> (dst IS computer)
  COLUMNS (
    u.user_domain,
    src.computer AS staging_host,
    dst.computer AS victim_host,
    a.time AS auth_time,
    c.time AS compromise_time
  )
);

--
-- Evidence trail around one confirmed chain (bind values from A)
--

SELECT *
FROM GRAPH_TABLE (
  lanl_cyber_graph
  MATCH (src IS computer WHERE src.computer = 'C17693')
          -[f IS flows_connected]->
        (dst IS computer WHERE dst.computer = 'C12682')
  COLUMNS (
    src.computer AS src_computer,
    dst.computer AS dst_computer,
    f.protocol,
    f.dst_port,
    f.byte_cnt,
    f.time
  )
);

--
-- Lookalike hunting (excludes known pairs)
--

SELECT *
FROM GRAPH_TABLE (
  lanl_cyber_graph
  MATCH (u IS user_domain) -[au IS auth_src_authenticated]-> (src IS computer)
          -[ac IS auth_connected]-> (dst IS computer)
  WHERE ac.time - au.time + 300                      -- 5 minute interval
  COLUMNS (
    u.user_domain,
    src.computer AS staging_host,
    dst.computer AS candidate_victim,
    ac.time
  )
) c
WHERE NOT EXISTS (
  SELECT 1
  FROM redteam r
  WHERE r.src_computer = c.staging_host AND r.dst_computer = c.candidate_victim
);