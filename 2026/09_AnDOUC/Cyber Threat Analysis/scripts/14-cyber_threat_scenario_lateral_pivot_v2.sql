/******************************************************************************
 *
 * Cyber Threat Scenario 2: Lateral Pivot / Broad Concentrated-Movement Triage
 * (a computer that reaches several other computers in a concentrated
 * one-hour window, including small movements that may require triage)
 *
 * Narrative:
 *   REDTEAM shows a small number of staging hosts responsible for many
 *   COMPROMISED edges. An attacker who obtained access to one host may use
 *   it to pivot outward, but ordinary infrastructure and small, concentrated
 *   movements can produce a similar fan-out signal. This script therefore
 *   (1) profiles known staging hosts from ground truth, (2) searches the full
 *   cyber graph for concentrated AUTH_CONNECTED fan-out, (3) excludes known
 *   staging hosts and confirmed buckets while preserving small candidates for
 *   broad triage, (4) pulls identity context around a selected bucket, and
 *   (5) enriches a candidate with multi-hop reach and structural importance.
 *
 *   C17693 remains the validated loud-beachhead reference (296 victims and
 *   30 of 69 active hours clearing a 5+/hour burst). This v2 intentionally
 *   has broader scope: a small, concentrated movement is a valid triage hit,
 *   but it is not treated as a C17693-equivalent beachhead. Step 4 identity
 *   context and Steps 5/6 reach and structural context help prioritize a
 *   review, but none of them independently proves a pivot. C19932 and C22409
 *   remain known, quieter examples and are calibration controls, not new
 *   candidates.
 *
 * Analysis flow:
 *   1. Shape Verification -- profile known staging hosts from ground truth.
 *   2. Broad Burst Detection -- find AUTH_CONNECTED fan-out of 5+ distinct
 *      target computers in one hour, independent of any label.
 *   3. New Triage Candidate Isolation -- exclude known staging hosts and
 *      confirmed buckets, return one representative bucket per host, and
 *      retain small concentrated movements for review.
 *   4. Identity Context -- identify user_domain authentication activity
 *      just before/during the selected bucket.
 *   5. Multi-Hop Reach -- enrich a candidate with its 1-2 hop AUTH_CONNECTED
 *      reach; this is context, not a hard exclusion.
 *   6. Structural Ranking -- provide PageRank context for the candidate and
 *      reached computers; do not treat a high score alone as proof.
 *
 * File name: 14-cyber_threat_scenario_lateral_pivot_v2.sql
 * Author: Karin Patenge (drafted with Claude Sonnet 5 Max)
 * Last updated: 2026-09-17
 *
 *****************************************************************************/

-------------------
-- Session settings
-------------------

ALTER SESSION FORCE PARALLEL QUERY PARALLEL 8;
ALTER SESSION ENABLE PARALLEL DDL;
ALTER SESSION ENABLE PARALLEL DML;

--------------------------------------------------------------------------
-- Step 1: Profile the known beachhead shape from ground truth
-- For each confirmed staging host, how many distinct victims did it
-- reach, and over what time span? This is the empirical shape-check the
-- rest of this scenario depends on: it measures the real pattern from
-- ground truth first, rather than assuming a threshold, and is the
-- reference shape Step 2 searches for across the full (unlabeled) cyber
-- graph.
--
-- Explanations:
-- A beachhead is the one staging computer an attacker reuses repeatedly
-- to pivot outward to many victims, with the pivot cascading across
-- several hops rather than stopping at direct targets.
--------------------------------------------------------------------------

SELECT
  staging_host,
  COUNT(DISTINCT victim_host)                 AS distinct_victims,
  MIN(compromise_time)                        AS first_compromise,
  MAX(compromise_time)                        AS last_compromise,
  MAX(compromise_time) - MIN(compromise_time) AS time_span_seconds
FROM
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH (src IS computer) -[c IS compromised]-> (dst IS computer)
    COLUMNS (
      src.computer AS staging_host,
      dst.computer AS victim_host,
      c.time       AS compromise_time
    )
  )
GROUP BY
  staging_host
ORDER BY
  distinct_victims DESC;

-- C17693 is the loud reference: 296 distinct victims over ~28 days, with
-- 30 of 69 active hours clearing 5+/hour. C19932 (8 victims, ~24 days)
-- and C22409 (3 victims, ~4 days) are quieter examples and never exceed
-- 2/hour. In this v2, Step 1 remains calibration context; Steps 2/3 are
-- broad triage queries and are not required to reproduce the full C17693
-- volume profile.

SELECT
  TRUNC(compromise_time / 3600) AS hour_bucket,
  COUNT(DISTINCT victim_host) AS victims_this_hour
FROM GRAPH_TABLE (
  lanl_ground_truth_graph
  MATCH (src IS computer WHERE src.computer = 'C17693') -[c IS compromised]-> (dst IS computer)
  COLUMNS (dst.computer AS victim_host, c.time AS compromise_time)
)
GROUP BY TRUNC(compromise_time / 3600)
ORDER BY victims_this_hour DESC;

SELECT
  TRUNC(compromise_time / 3600) AS hour_bucket,
  COUNT(DISTINCT victim_host) AS victims_this_hour
FROM GRAPH_TABLE (
  lanl_ground_truth_graph
  MATCH (src IS computer WHERE src.computer = 'C19932') -[c IS compromised]-> (dst IS computer)
  COLUMNS (dst.computer AS victim_host, c.time AS compromise_time)
)
GROUP BY TRUNC(compromise_time / 3600)
ORDER BY victims_this_hour DESC;

SELECT
  TRUNC(compromise_time / 3600) AS hour_bucket,
  COUNT(DISTINCT victim_host) AS victims_this_hour
FROM GRAPH_TABLE (
  lanl_ground_truth_graph
  MATCH (src IS computer WHERE src.computer = 'C22409') -[c IS compromised]-> (dst IS computer)
  COLUMNS (dst.computer AS victim_host, c.time AS compromise_time)
)
GROUP BY TRUNC(compromise_time / 3600)
ORDER BY victims_this_hour DESC;

-- RESOLVED: C17693 clears 5+/hour on 30 of its 69 active COMPROMISED hours
-- in recurring clusters across the whole ~28-day span, not one lucky hour.
-- C19932 and C22409 never exceed 2 distinct COMPROMISED victims in one hour.
-- The later AUTH_CONNECTED calibration is broader: C17693 has 525 overall
-- targets and peaks at 67/hour, while C19932 and C22409 each have 24 overall
-- targets and peak at 17/hour. Therefore the 5+/hour AUTH_CONNECTED signal
-- is a triage threshold, not a compromised-edge label or a C17693 classifier.

--------------------------------------------------------------------------
-- Step 2: Broad burst detection -- find computer-to-computer fan-out in
-- the full cyber graph via AUTH_CONNECTED, independent of the REDTEAM label.
-- A computer that authenticates-connects to 5+ distinct other computers
-- within one hour is a triage signal, not proof of a pivot.
--
-- Confirmed against ground truth (Step 1): C17693 clears this floor in
-- recurring clusters of COMPROMISED edges. In the broader AUTH_CONNECTED
-- graph, C19932 and C22409 also clear the floor, reaching 17 targets/hour
-- with 24 overall targets. This demonstrates that AUTH_CONNECTED is broader
-- than the ground-truth compromise signal. Cross-reference with identity
-- evidence in Step 4 and reach context in Steps 5/6 when it is noisy.
--
-- distinct_targets_overall is context: a host that connects to hundreds of
-- computers as normal, everyday behavior (a DC, file server, backup job)
-- will trip an hourly ">=5" threshold constantly. Conversely, a host with
-- only 5-8 total targets may be a small concentrated movement or routine
-- activity. Step 3 returns one representative bucket per host and exposes
-- the number of qualifying buckets so analysts can make that distinction.
--
-- FINAL OBSERVATION: the Step 2 sample contains the confirmed reference
-- activity plus many unlabeled low-baseline rows. The unlabeled population is
-- intentionally carried into Step 3 rather than being treated as confirmed
-- lateral movement.
--------------------------------------------------------------------------

WITH computer_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (src IS computer) -[e IS auth_connected]-> (dst IS computer)
      COLUMNS (
        src.computer AS staging_host,
        dst.computer AS candidate_victim,
        e.time       AS conn_time,
        e.redteam    AS is_confirmed_redteam
      )
    )
),
host_baseline AS (
  SELECT
    staging_host,
    COUNT(DISTINCT candidate_victim) AS distinct_targets_overall
  FROM
    computer_edges
  GROUP BY
    staging_host
),
bucketed AS (
  SELECT
    staging_host,
    TRUNC(conn_time / 3600)          AS time_bucket,
    COUNT(DISTINCT candidate_victim) AS distinct_targets_in_bucket,
    MAX(is_confirmed_redteam)        AS bucket_has_confirmed_redteam_event
  FROM
    computer_edges
  GROUP BY
    staging_host,
    TRUNC(conn_time / 3600)
)
SELECT
  b.*,
  hb.distinct_targets_overall
FROM
  bucketed b
  JOIN host_baseline hb ON hb.staging_host = b.staging_host
WHERE
  distinct_targets_in_bucket >= 5   -- threshold: pivoting to 5+ distinct computers inside one hour
ORDER BY
  bucket_has_confirmed_redteam_event DESC,
  distinct_targets_overall ASC,     -- de-prioritize hosts that are always chatty -- see Step 3a
  distinct_targets_in_bucket DESC
FETCH FIRST 200 ROWS ONLY;          -- limit to a manageable number of candidates for further investigation

--------------------------------------------------------------------------
-- Step 3: Isolate NEW broad-triage candidates.
--
-- Keep the same low floor as Step 2 (5 distinct targets in one hour), but
-- do not claim that every result is a beachhead. Exclude hosts that are
-- already known staging hosts and buckets containing a confirmed REDTEAM
-- AUTH_CONNECTED event. The remaining rows are unlabeled triage windows.
--
-- This version returns ONE representative (strongest) bucket per host,
-- rather than spending the FETCH limit on repeated buckets from the same
-- host. qualifying_bucket_count shows whether the signal is isolated or
-- recurring. distinct_targets_overall remains context only: small hosts
-- are valid broad-triage candidates, while very chatty hosts still need
-- caution because their hourly fan-out may be routine infrastructure.
--------------------------------------------------------------------------

-- FINAL OBSERVATION: Step 3 returned 500 rows for 500 unique hosts. Because
-- the result is ordered by distinct_targets_overall ASC before FETCH, this is
-- the lowest-baseline slice: the returned hosts have 5-11 overall targets.
-- 182 hosts have one qualifying bucket, while 318 have recurring qualifying
-- buckets; 136 have at least 10 qualifying buckets and 55 have at least 25.
-- The result is therefore a broad low-volume triage population, not a list of
-- 500 confirmed beachheads. C15758 (5 overall targets, one bucket) is an
-- isolated candidate; C5868 (6 overall targets, 23 buckets) is a recurring
-- comparison candidate.

WITH computer_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (src IS computer) -[e IS auth_connected]-> (dst IS computer)
      COLUMNS (
        src.computer AS staging_host,
        dst.computer AS candidate_victim,
        e.time       AS conn_time,
        e.redteam    AS is_confirmed_redteam
      )
    )
),
host_baseline AS (
  SELECT
    staging_host,
    COUNT(DISTINCT candidate_victim) AS distinct_targets_overall
  FROM
    computer_edges
  GROUP BY
    staging_host
),
bucketed AS (
  SELECT
    staging_host,
    TRUNC(conn_time / 3600)          AS time_bucket,
    COUNT(DISTINCT candidate_victim) AS distinct_targets_in_bucket
  FROM computer_edges
  GROUP BY staging_host, TRUNC(conn_time / 3600)
  HAVING NVL(MAX(is_confirmed_redteam), 0) = 0 -- retain buckets without a confirmed REDTEAM auth event
     AND COUNT(DISTINCT candidate_victim) >= 5
),
ranked_candidates AS (
  SELECT
    b.staging_host,
    b.time_bucket,
    b.distinct_targets_in_bucket,
    hb.distinct_targets_overall,
    COUNT(*) OVER (
      PARTITION BY b.staging_host
    ) AS qualifying_bucket_count,
    ROW_NUMBER() OVER (
      PARTITION BY b.staging_host
      ORDER BY
        b.distinct_targets_in_bucket DESC,
        b.time_bucket
    ) AS host_bucket_rank
  FROM
    bucketed b
    JOIN host_baseline hb
      ON hb.staging_host = b.staging_host
  WHERE
    NOT EXISTS (
      SELECT 1
      FROM
        GRAPH_TABLE (
          lanl_ground_truth_graph
          MATCH (src IS computer) -[c IS compromised]-> (dst IS computer)
          COLUMNS (src.computer AS known_staging_host)
        ) known
      WHERE
        known.known_staging_host = b.staging_host
    )
)
SELECT
  staging_host,
  time_bucket,
  distinct_targets_in_bucket,
  distinct_targets_overall,
  qualifying_bucket_count
FROM
  ranked_candidates
WHERE
  host_bucket_rank = 1
ORDER BY
  distinct_targets_overall ASC,          -- begin with small, concentrated movements
  distinct_targets_in_bucket DESC,
  qualifying_bucket_count DESC,
  staging_host
FETCH FIRST 500 ROWS ONLY;                -- 500 unique hosts, not 500 bucket rows

--------------------------------------------------------------------------
-- Step 3a (diagnostic): where do the known staging hosts rank within the
-- broad 5+/hour population? C17693 is the loud reference; C19932 and
-- C22409 illustrate quieter movements that this v2 may still surface only
-- when they are represented by AUTH_CONNECTED activity.
--
-- volume_rank: rank purely by burst volume (distinct_targets_in_bucket).
-- This is useful for seeing the largest bursts, but high-fan-out
-- infrastructure (e.g. C1798, C1521 from an earlier run) can dominate it.
--
-- fan_out_rank: rank by distinct_targets_overall ASC instead. This puts
-- small concentrated movements first for broad triage, while exposing the
-- host baseline needed to recognize ordinary infrastructure.
--
-- FINAL OBSERVATION: the diagnostic population contains 867,238 qualifying
-- bucket rows. C17693's 67-target peak ranks 350 by burst volume, while the
-- 17-target peaks of C19932/C22409 rank 6,512. These are bucket-level ranks,
-- not unique-host ranks. Some buckets for the known hosts have no REDTEAM
-- flag, which confirms that Step 3 must exclude known staging hosts at the
-- host level in addition to excluding confirmed buckets.
--------------------------------------------------------------------------

WITH computer_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (src IS computer) -[e IS auth_connected]-> (dst IS computer)
      COLUMNS (
        src.computer AS staging_host,
        dst.computer AS candidate_victim,
        e.time       AS conn_time,
        e.redteam    AS is_confirmed_redteam
      )
    )
),
host_baseline AS (
  SELECT
    staging_host,
    COUNT(DISTINCT candidate_victim) AS distinct_targets_overall
  FROM
    computer_edges
  GROUP BY
    staging_host
),
bucketed AS (
  SELECT
    staging_host,
    TRUNC(conn_time / 3600)          AS time_bucket,
    COUNT(DISTINCT candidate_victim) AS distinct_targets_in_bucket,
    MAX(is_confirmed_redteam)        AS bucket_has_confirmed_redteam_event
  FROM
    computer_edges
  GROUP BY
    staging_host,
    TRUNC(conn_time / 3600)
  HAVING
    COUNT(DISTINCT candidate_victim) >= 5   -- same candidate population Step 2/3 already use
),
ranked AS (
  SELECT
    b.*,
    hb.distinct_targets_overall,
    RANK() OVER (ORDER BY b.distinct_targets_in_bucket DESC) AS volume_rank,
    RANK() OVER (ORDER BY hb.distinct_targets_overall ASC)   AS fan_out_rank,
    COUNT(*) OVER ()                                         AS total_candidate_buckets
  FROM
    bucketed b
    JOIN host_baseline hb ON hb.staging_host = b.staging_host
)
SELECT *
FROM ranked
WHERE
  staging_host IN ('C17693', 'C19932', 'C22409')
ORDER BY
  distinct_targets_in_bucket DESC;

--------------------------------------------------------------------------
-- Step 4: Identity context for a broad-triage candidate.
-- Which user_domain authenticated to the candidate staging host just
-- before/during the selected bucket? This is supporting evidence, not by
-- itself proof that the activity is fraudulent. Keep the auth status and
-- orientation visible so an analyst can distinguish successful logons,
-- failures, and other authentication activity.
--
-- Replace the bind values with the same row from Step 3's output:
--   :candidate_staging_host
--   :time_bucket
--
-- FINAL REVIEW BINDINGS (run one candidate at a time):
--   primary candidate:    :candidate_staging_host = 'C15758', :time_bucket = 302
--   comparison candidate: :candidate_staging_host = 'C5868',  :time_bucket = 160
--
-- FINAL OBSERVATIONS: C15758 had successful Network logons and TGS activity
-- from C22621$ plus user-style accounts U3771 and U6448, mostly Kerberos with
-- some NTLM. C5868 had recurring successful Network logons from machine
-- accounts C1065$, C529$, C586$, C612$, C457$, and C1640$, using
-- MICROSOFT_AUTHENTICATION_PACKAGE_V1_0. The C15758 identity mix is the more
-- interesting triage signal; the C5868 machine-only pattern supports its
-- interpretation as recurring infrastructure. Authentication context is
-- corroboration, not proof of which identity caused the outbound fan-out.
--------------------------------------------------------------------------

SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (u IS user_domain) -[a IS auth_src_authenticated]-> (c IS computer)
    WHERE
      c.computer = :candidate_staging_host
      AND a.time BETWEEN (:time_bucket * 3600) - 1800 AND (:time_bucket * 3600) + 3600
    COLUMNS (
      u.user_domain AS suspect_user_domain,
      c.computer    AS staging_host,
      a.time        AS auth_time,
      a.logon_type      AS logon_type,
      a.auth_type       AS auth_type,
      a.auth_orientation AS auth_orientation,
      a.success_failure  AS success_failure
    )
  )
ORDER BY
  auth_time;

--------------------------------------------------------------------------
-- Step 5: Multi-hop reach enrichment for a triage candidate.
-- Separate direct AUTH_CONNECTED reach from computers reachable only through
-- a second AUTH_CONNECTED hop. The earlier combined 1-2 hop count was useful
-- as a broad signal, but C15758 and C5868 both returned 105 computers; that
-- result is therefore dominated by common graph topology and does not by
-- itself distinguish candidates.
--
-- The result includes one SUMMARY row followed by one row per reached
-- computer. MIN_HOP identifies the shortest observed reach (1 or 2), while
-- REACH_CLASS shows whether the computer is direct-only, reachable at both
-- depths, or two-hop-only. The summary counts two-hop-only computers and the
-- direct/two-hop overlap separately, and reports the total-to-direct ratio.
--
-- For each two-hop endpoint, INTERMEDIATE_COMPUTERS lists the computers that
-- can provide the second-hop expansion. This is context for identifying hub
-- inflation; it is not an ordered path. The query deliberately does not label
-- any reachable computer as malicious.
--
-- Simple-path guards exclude self-reach and repeated-vertex paths. Without
-- them, a direct target with an AUTH_CONNECTED self-loop could appear as both
-- a direct and two-hop target even though no additional computer was reached.
--
-- Replace the bind value with a row from Step 3's output before running.
--
-- FINAL REVIEW BINDINGS (run one candidate at a time):
--   primary candidate:    :candidate_staging_host = 'C15758'
--   comparison candidate: :candidate_staging_host = 'C5868'
--
-- FINAL OBSERVATIONS: C15758 returned 5 direct computers, 100 two-hop-only
-- computers, 3 direct/two-hop overlaps, and 105 total computers (21x the
-- direct reach). C5868 returned 6 direct, 99 two-hop-only, 6 overlaps, and
-- the same 105 total (17.5x). The equal totals show that reach volume is
-- largely a graph-topology signal. C15758 has partial direct-target overlap
-- through C457/C467/C528, whereas all six C5868 direct targets participate
-- in valid two-hop paths and its Step 4 identities are machine accounts.
--
-- ON OVERFLOW TRUNCATE WITH COUNT: the per-endpoint intermediate list is
-- capped at 4000 bytes. The counts remain exact even if the display list is
-- truncated.
--------------------------------------------------------------------------

WITH direct_reach AS (
  SELECT DISTINCT
    staging_host,
    reached_computer
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (src IS computer WHERE src.computer = :candidate_staging_host)
              -[e IS auth_connected]-> (reached IS computer)
      COLUMNS (
        src.computer     AS staging_host,
        reached.computer AS reached_computer
      )
    )
  WHERE
    reached_computer <> staging_host
),
two_hop_paths AS (
  SELECT
    staging_host,
    intermediate_computer,
    reached_computer
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (src IS computer WHERE src.computer = :candidate_staging_host)
              -[e1 IS auth_connected]-> (mid IS computer)
              -[e2 IS auth_connected]-> (reached IS computer)
      COLUMNS (
        src.computer     AS staging_host,
        mid.computer     AS intermediate_computer,
        reached.computer AS reached_computer
      )
    )
  WHERE
    intermediate_computer <> staging_host
    AND reached_computer <> staging_host
    AND reached_computer <> intermediate_computer
),
two_hop_reach AS (
  SELECT DISTINCT
    staging_host,
    reached_computer
  FROM
    two_hop_paths
),
two_hop_target_detail AS (
  SELECT
    staging_host,
    reached_computer,
    COUNT(DISTINCT intermediate_computer) AS two_hop_intermediate_count,
    LISTAGG(
      DISTINCT intermediate_computer,
      ', ' ON OVERFLOW TRUNCATE WITH COUNT
    ) AS intermediate_computers
  FROM
    two_hop_paths
  GROUP BY
    staging_host,
    reached_computer
),
reach_by_computer AS (
  SELECT
    staging_host,
    reached_computer,
    1 AS hop_count
  FROM
    direct_reach
  UNION ALL
  SELECT
    staging_host,
    reached_computer,
    2 AS hop_count
  FROM
    two_hop_reach
),
min_hop_reach AS (
  SELECT
    staging_host,
    reached_computer,
    MIN(hop_count) AS min_hop
  FROM
    reach_by_computer
  GROUP BY
    staging_host,
    reached_computer
),
classified_reach AS (
  SELECT
    m.staging_host,
    m.reached_computer,
    m.min_hop,
    CASE
      WHEN m.min_hop = 1 AND d.reached_computer IS NOT NULL
        THEN 'DIRECT_AND_TWO_HOP'
      WHEN m.min_hop = 1
        THEN 'DIRECT_ONLY'
      ELSE 'TWO_HOP_ONLY'
    END AS reach_class,
    d.two_hop_intermediate_count,
    d.intermediate_computers
  FROM
    min_hop_reach m
    LEFT JOIN two_hop_target_detail d
      ON d.staging_host = m.staging_host
     AND d.reached_computer = m.reached_computer
),
reach_metrics AS (
  SELECT
    c.*,
    COUNT(CASE WHEN min_hop = 1 THEN 1 END)
      OVER (PARTITION BY staging_host) AS direct_computers_reached,
    COUNT(CASE WHEN min_hop = 2 THEN 1 END)
      OVER (PARTITION BY staging_host) AS two_hop_only_computers_reached,
    COUNT(CASE WHEN reach_class = 'DIRECT_AND_TWO_HOP' THEN 1 END)
      OVER (PARTITION BY staging_host) AS direct_two_hop_overlap,
    COUNT(*) OVER (PARTITION BY staging_host) AS distinct_computers_reached
  FROM
    classified_reach c
)
SELECT
  result_type,
  staging_host,
  reached_computer,
  min_hop,
  reach_class,
  direct_computers_reached,
  two_hop_only_computers_reached,
  direct_two_hop_overlap,
  distinct_computers_reached,
  ROUND(
    distinct_computers_reached / NULLIF(direct_computers_reached, 0),
    2
  ) AS total_to_direct_ratio,
  two_hop_intermediate_count,
  intermediate_computers
FROM (
  SELECT
    'SUMMARY' AS result_type,
    staging_host,
    CAST(NULL AS VARCHAR2(128)) AS reached_computer,
    CAST(NULL AS NUMBER) AS min_hop,
    'SUMMARY' AS reach_class,
    MAX(direct_computers_reached)       AS direct_computers_reached,
    MAX(two_hop_only_computers_reached) AS two_hop_only_computers_reached,
    MAX(direct_two_hop_overlap)        AS direct_two_hop_overlap,
    MAX(distinct_computers_reached)    AS distinct_computers_reached,
    CAST(NULL AS NUMBER) AS total_to_direct_ratio,
    CAST(NULL AS NUMBER) AS two_hop_intermediate_count,
    CAST(NULL AS VARCHAR2(4000)) AS intermediate_computers
  FROM
    reach_metrics
  GROUP BY
    staging_host
  UNION ALL
  SELECT
    'REACH_DETAIL' AS result_type,
    staging_host,
    reached_computer,
    min_hop,
    reach_class,
    direct_computers_reached,
    two_hop_only_computers_reached,
    direct_two_hop_overlap,
    distinct_computers_reached,
    ROUND(
      distinct_computers_reached / NULLIF(direct_computers_reached, 0),
      2
    ) AS total_to_direct_ratio,
    two_hop_intermediate_count,
    intermediate_computers
  FROM
    reach_metrics
)
ORDER BY
  CASE result_type WHEN 'SUMMARY' THEN 0 ELSE 1 END,
  min_hop,
  reached_computer
FETCH FIRST 201 ROWS ONLY;  -- summary plus up to 200 reachable computers

--------------------------------------------------------------------------
-- Step 6: Quantify reach -- rank the candidate staging host and every
-- computer it can reach (Step 5's simple 1-2 hop walk) with PageRank on the
-- full cyber graph. This is prioritization context for broad triage: a high
-- PageRank target may increase impact, but it is not proof of maliciousness.
--
-- The reach set uses the same repeated-vertex exclusions as Step 5 and
-- exposes MIN_HOP and REACH_CLASS, so direct targets can be distinguished
-- from computers reached only through a second hop. The candidate host is
-- included with MIN_HOP = 0.
--
-- Originally this step took 2 hand-picked computers via bind variables -- the
-- same limitation Scenario 1's Step 6 had before its fix. This version pulls
-- the full cleaned reach set programmatically and computes PageRank once,
-- joined against the staging host plus every reached computer.
-- Watch for the same hub-inflation risk Scenario 1 found with C586: on a
-- well-connected graph, a multi-hop walk can reach a high-PageRank hub
-- incidentally, not because this specific movement is unusually dangerous.
-- Cross-check Step 3's host baseline, Step 4's identity evidence, and Step
-- 5's reach class before treating a high score as significant on its own.
--
-- FINAL REVIEW BINDING (run one candidate at a time):
--   primary candidate:    :candidate_staging_host = 'C15758'
--   comparison candidate: :candidate_staging_host = 'C5868'
--
-- FINAL OBSERVATION FOR C15758: the highest PageRank computers were mostly
-- two-hop-only or shared hubs (C586, C612, C529, C625), followed by direct
-- hubs C467, C457, and C528. C15758 itself had very low PageRank. PageRank
-- therefore supplies structural context, not candidate-specific proof; a
-- high score for a two-hop hub must not outweigh the Step 3/4 evidence.
--------------------------------------------------------------------------

ALTER SESSION DISABLE PARALLEL QUERY;

WITH direct_reach AS (
  SELECT DISTINCT
    staging_host,
    reached_computer
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (src IS computer WHERE src.computer = :candidate_staging_host)
              -[e IS auth_connected]-> (reached IS computer)
      COLUMNS (
        src.computer     AS staging_host,
        reached.computer AS reached_computer
      )
    )
  WHERE
    reached_computer <> staging_host
),
two_hop_paths AS (
  SELECT
    staging_host,
    intermediate_computer,
    reached_computer
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (src IS computer WHERE src.computer = :candidate_staging_host)
              -[e1 IS auth_connected]-> (mid IS computer)
              -[e2 IS auth_connected]-> (reached IS computer)
      COLUMNS (
        src.computer     AS staging_host,
        mid.computer     AS intermediate_computer,
        reached.computer AS reached_computer
      )
    )
  WHERE
    intermediate_computer <> staging_host
    AND reached_computer <> staging_host
    AND reached_computer <> intermediate_computer
),
two_hop_reach AS (
  SELECT DISTINCT
    staging_host,
    reached_computer
  FROM
    two_hop_paths
),
reach_by_computer AS (
  SELECT
    staging_host,
    reached_computer,
    1 AS hop_count
  FROM
    direct_reach
  UNION ALL
  SELECT
    staging_host,
    reached_computer,
    2 AS hop_count
  FROM
    two_hop_reach
),
min_hop_reach AS (
  SELECT
    staging_host,
    reached_computer,
    MIN(hop_count) AS min_hop
  FROM
    reach_by_computer
  GROUP BY
    staging_host,
    reached_computer
),
classified_reach AS (
  SELECT
    m.staging_host,
    m.reached_computer,
    m.min_hop,
    CASE
      WHEN m.min_hop = 1 AND t.reached_computer IS NOT NULL
        THEN 'DIRECT_AND_TWO_HOP'
      WHEN m.min_hop = 1
        THEN 'DIRECT_ONLY'
      ELSE 'TWO_HOP_ONLY'
    END AS reach_class
  FROM
    min_hop_reach m
    LEFT JOIN two_hop_reach t
      ON t.staging_host = m.staging_host
     AND t.reached_computer = m.reached_computer
),
candidate_reach AS (
  SELECT
    :candidate_staging_host AS computer,
    0 AS min_hop,
    'STAGING_HOST' AS role,
    'STAGING_HOST' AS reach_class
  FROM DUAL
  UNION ALL
  SELECT
    reached_computer AS computer,
    min_hop,
    'REACHED' AS role,
    reach_class
  FROM
    classified_reach
),
computer_importance AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      DBMS_OGA.PAGERANK (
        lanl_cyber_graph,
        PROPERTY (VERTEX OUTPUT rank),
        10, 1.0, 0.85d, FALSE
      )
      MATCH (c IS computer)
      COLUMNS (
        c.computer AS computer,
        c.rank     AS pagerank_score
      )
    )
)
SELECT
  r.computer,
  r.role,
  r.min_hop,
  r.reach_class,
  imp.pagerank_score
FROM
  candidate_reach r
  JOIN computer_importance imp ON imp.computer = r.computer
ORDER BY
  imp.pagerank_score DESC
FETCH FIRST 200 ROWS ONLY;  -- limit to a manageable number

--------------------------------------------------------------------------
-- Scope resolution and triage interpretation
--
-- The historical validation below explains why Step 3 is a triage detector
-- rather than a standalone beachhead classifier. Host-to-host fan-out does
-- not reliably separate quiet secondary compromises from ordinary
-- infrastructure, so small results must be corroborated with Step 4/5.
--
--   1. C19932 and C22409 max out at 2 distinct victims/hour in the ground-
--      truth COMPROMISED data, but their broader AUTH_CONNECTED projections
--      do enter the 5+/hour population. They are calibration controls, not
--      new candidates.
--   2. Daily fan-out and daily "new relationship" metrics were noisy at
--      full graph scale, including genuinely huge hosts such as C1798.
--   3. Banding novelty and adding an overall-fan-out floor relocated the
--      pollution rather than removing it; a floor can become a new wall.
--   4. Cross-referencing Scenario 1's persistence candidates against
--      AUTH_CONNECTED onward reach produced 525/24/24 for C17693/C19932/
--      C22409, while C1798 alone produced 8,052.
--   5. The final broad-triage comparison produced 5/100/3/105 for C15758
--      (direct/two-hop-only/overlap/total) and 6/99/6/105 for C5868. C15758
--      had an isolated burst and mixed machine/user-style identity context;
--      C5868 had recurring activity and machine-only identity context.
--   6. Step 6 showed that PageRank is dominated by shared two-hop hubs. It is
--      useful for structural context, but it cannot independently confirm a
--      pivot.
--
-- Conclusion: Step 3 v2 intentionally keeps both small and large
-- concentrated movements. Use qualifying_bucket_count, Step 4 identity
-- status/orientation, Step 5 direct-versus-two-hop structure, and Step 6
-- PageRank context to prioritize and investigate them. In the final review,
-- C15758 is the stronger broad-triage candidate; C5868 is a useful recurring
-- infrastructure comparison. Neither is a confirmed beachhead from this
-- workflow alone.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Next steps (require confirming exact DBMS_OGA/DBMS_GAF parameter
-- signatures for this release before use -- not run here since only
-- PAGERANK's signature is proven working in 12-query_graphs.sql):
--   - PERSONALIZED_PAGERANK_SET seeded on all Step-3 candidate victims,
--     to rank every computer in the graph by relevance to this pivot as
--     a whole rather than one PageRank pass per candidate.
--   - BELLMAN_FORD from the candidate staging host to the highest-PageRank
--     computers, to report the pivot's distance from the crown jewels.
--     Tried in Scenario 1 (13-cyber_threat_scenario_credential_theft.sql) and
--     removed: length_property needs a real, existing numeric edge
--     property -- a nonexistent property name plus DEFAULT ON NULL 1 (to
--     fake a uniform hop-count weight) did not work there. AUTH_CONNECTED
--     itself only carries (id, time, src_computer, dst_computer, redteam)
--     -- no obvious weight among those either -- confirm what
--     DEFAULT ON NULL actually requires before retrying here.
--------------------------------------------------------------------------
