/******************************************************************************
 *
 * Cyber Threat Scenario 2: C17693-Like Lateral Pivot / Beachhead Reuse
 * (a new staging host showing a recurring, high-volume fan-out burst)
 *
 * Narrative:
 *   REDTEAM shows a small number of staging hosts responsible for many
 *   COMPROMISED edges -- an attacker who fraudulently obtained access to
 *   one host uses it as a beachhead to pivot outward to many victims, and
 *   the pivot can cascade across several hops. This script (1) profiles the
 *   known C17693 shape from ground truth, (2) measures the equivalent
 *   AUTH_CONNECTED profile, (3) excludes known staging hosts and confirmed
 *   buckets, and (4) ranks new hosts by similarity to C17693 before pulling
 *   identity, multi-hop reach, and structural evidence.
 *
 *   SCOPE: C17693 is the validated reference (296 victims and 30 of 69
 *   active hours clearing a 5+/hour burst). In ground-truth COMPROMISED
 *   data, C19932 (8 victims) and C22409 (3 victims) never clear the hourly
 *   volume floor and are retained as negative controls. v1 is intentionally high-precision: it uses the
 *   C17693 AUTH_CONNECTED profile to prioritize new hosts with recurring,
 *   high-volume bursts. Small one-off movements belong in v2 broad triage.
 *
 * Analysis flow:
 *   1. Shape Verification -- profile known staging hosts from ground truth.
 *   2. C17693 Reference Profile -- measure its AUTH_CONNECTED baseline,
 *      burst size, and recurrence.
 *   3. Strict New Candidate Isolation -- keep only new hosts with recurring
 *      clean bursts and rank them by distance from C17693's profile.
 *   4. Identity Behind the Beachhead -- identify the user_domain associated
 *      with the selected peak bucket.
 *   5. Multi-Hop Reach -- measure whether the candidate can cascade beyond
 *      its direct targets.
 *   6. Structural Ranking -- provide PageRank context for reached assets.
 *
 * File name: 14-cyber_threat_scenario_lateral_pivot_v1.sql
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

-- C17693 is the reference beachhead for this v1: 296 distinct victims over
-- ~28 days, with 30 of 69 active hours clearing 5+/hour. C19932 (8 victims,
-- ~24 days) and C22409 (3 victims, ~4 days) are negative controls; neither
-- exceeds 2 victims in an hour. Steps 2/3 therefore use C17693 as the
-- profile to match, rather than treating 5+/hour alone as sufficient.


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

-- RESOLVED: ran against all three known hosts. C17693 clears 5+/hour on
-- 30 of its 69 active hours -- the hourly threshold is real for this host,
-- in recurring clusters across the whole ~28-day span, not one lucky hour.
-- C19932 and C22409 never exceed 2 distinct victims in any single hour.
-- v1 uses that contrast to require recurring, C17693-like AUTH_CONNECTED
-- behavior; v2 remains available when the investigation should retain
-- smaller concentrated movements.

--------------------------------------------------------------------------
-- Step 2: Build the C17693 reference population -- find computer-to-computer
-- fan-out bursts in the full cyber graph via AUTH_CONNECTED, independent of
-- the REDTEAM label. The 5+ target count is only the entry floor; Step 3
-- requires recurring, high-volume behavior comparable to C17693.
--
-- Confirmed against ground truth (Step 1): C17693 clears this floor in
-- recurring clusters, while C19932 and C22409 never reach it in the
-- COMPROMISED data. The broader AUTH_CONNECTED output can still show
-- 5+ bursts for these controls, so this step is only a reference-population
-- and calibration query; strict C17693-like filtering is applied in Step 3.
-- Cross-reference with FLOWS_CONNECTED if AUTH_CONNECTED alone is too noisy.
--
-- distinct_targets_overall is needed to recognize infrastructure noise: a
-- host that connects to hundreds of computers as normal, everyday behavior
-- will trip an hourly ">=5" threshold constantly. Step 3 compares this
-- baseline, burst size, and recurrence to C17693 instead of using the raw
-- burst count alone.
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

-- FINAL OUTPUT INTERPRETATION:
--   C17693 has 525 distinct AUTH_CONNECTED targets overall and a peak of 67
--   distinct targets in one hourly bucket. C19932 and C22409 each have 24
--   overall targets and a peak of 17 in the broader AUTH_CONNECTED data;
--   these rows are calibration controls, not proof that they are C17693-like.
--   The visible unknown hosts are mostly small (overall fan-out 5-7), which
--   is why recurrence, peak size, and profile distance are applied in Step 3.
--   Step 2 is an entry population and calibration output, not the final rank.

--------------------------------------------------------------------------
-- Step 3: Isolate NEW C17693-like beachhead candidates.
--
-- The 5-target hourly floor is only the entry point. A C17693-like host
-- must also show recurring clean burst buckets. This query builds the
-- C17693 reference profile from the same AUTH_CONNECTED data used for
-- candidates, then ranks new hosts by normalized distance from that
-- profile across. Because C17693's own qualifying buckets are confirmed
-- REDTEAM buckets, its reference profile is built before the clean-bucket
-- exclusion; only unknown candidates are required to be clean.
--
-- The profile distance uses:
--   * distinct_targets_overall       -- total host fan-out
--   * max_targets_in_bucket          -- strongest hourly burst
--   * qualifying_bucket_count        -- recurrence of clean 5+ bursts
--
-- A minimum of two qualifying buckets is applied to remove one-off bursts.
-- This is intentionally high-precision. Use v2 when small, isolated
-- movements should remain in the review population.
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
  FROM computer_edges
  GROUP BY staging_host, TRUNC(conn_time / 3600)
),
clean_buckets AS (
  SELECT
    staging_host,
    time_bucket,
    distinct_targets_in_bucket
  FROM
    bucketed
  WHERE
    NVL(bucket_has_confirmed_redteam_event, 0) = 0
    AND distinct_targets_in_bucket >= 5
),
reference_buckets AS (
  SELECT
    staging_host,
    time_bucket,
    distinct_targets_in_bucket
  FROM
    bucketed
  WHERE
    staging_host = 'C17693'
    AND distinct_targets_in_bucket >= 5
),
host_profiles AS (
  SELECT
    cb.staging_host,
    hb.distinct_targets_overall,
    COUNT(*)                           AS qualifying_bucket_count,
    MAX(cb.distinct_targets_in_bucket) AS max_targets_in_bucket,
    AVG(cb.distinct_targets_in_bucket) AS avg_targets_in_bucket
  FROM
    clean_buckets cb
    JOIN host_baseline hb
      ON hb.staging_host = cb.staging_host
  GROUP BY
    cb.staging_host,
    hb.distinct_targets_overall
  HAVING
    COUNT(*) >= 2                 -- require recurrence, not a one-off burst
),
reference_profile AS (
  SELECT
    hb.distinct_targets_overall AS ref_distinct_targets_overall,
    COUNT(*)                    AS ref_qualifying_bucket_count,
    MAX(rb.distinct_targets_in_bucket) AS ref_max_targets_in_bucket
  FROM
    reference_buckets rb
    JOIN host_baseline hb
      ON hb.staging_host = rb.staging_host
  GROUP BY
    hb.distinct_targets_overall
),
known_staging_hosts AS (
  SELECT DISTINCT
    staging_host
  FROM
    GRAPH_TABLE (
      lanl_ground_truth_graph
      MATCH (src IS computer) -[c IS compromised]-> (dst IS computer)
      COLUMNS (src.computer AS staging_host)
    )
),
ranked_candidates AS (
  SELECT
    hp.staging_host,
    cb.time_bucket,
    cb.distinct_targets_in_bucket,
    hp.distinct_targets_overall,
    hp.qualifying_bucket_count,
    hp.max_targets_in_bucket,
    hp.avg_targets_in_bucket,
    (
      ABS(hp.distinct_targets_overall - rp.ref_distinct_targets_overall)
        / NULLIF(rp.ref_distinct_targets_overall, 0)
      + ABS(hp.max_targets_in_bucket - rp.ref_max_targets_in_bucket)
        / NULLIF(rp.ref_max_targets_in_bucket, 0)
      + ABS(hp.qualifying_bucket_count - rp.ref_qualifying_bucket_count)
        / NULLIF(rp.ref_qualifying_bucket_count, 0)
    ) AS c17693_profile_distance,
    ROW_NUMBER() OVER (
      PARTITION BY hp.staging_host
      ORDER BY
        cb.distinct_targets_in_bucket DESC,
        cb.time_bucket
    ) AS host_bucket_rank
  FROM
    host_profiles hp
    JOIN clean_buckets cb
      ON cb.staging_host = hp.staging_host
    CROSS JOIN reference_profile rp
  WHERE
    NOT EXISTS (
      SELECT 1
      FROM known_staging_hosts k
      WHERE k.staging_host = hp.staging_host
    )
)
SELECT
  staging_host,
  time_bucket,
  distinct_targets_in_bucket,
  distinct_targets_overall,
  qualifying_bucket_count,
  max_targets_in_bucket,
  avg_targets_in_bucket,
  ROUND(c17693_profile_distance, 4) AS c17693_profile_distance
FROM
  ranked_candidates
WHERE
  host_bucket_rank = 1
ORDER BY
  c17693_profile_distance ASC,
  max_targets_in_bucket DESC,
  qualifying_bucket_count DESC,
  staging_host
FETCH FIRST 200 ROWS ONLY;       -- 200 unique new hosts closest to C17693's profile

-- FINAL OUTPUT INTERPRETATION:
--   The inferred C17693 reference is 525 overall targets, a maximum hourly
--   burst of 67, and 42 qualifying >=5-target buckets. The closest returned
--   candidates were C5400 / bucket 326 (51 in-bucket, 70 overall, 50
--   qualifying buckets, max 51, average 6.88, distance 1.2959) and C3435 /
--   bucket 206 (82 in-bucket, 103 overall, 66 qualifying buckets, max 82,
--   average 8.00, distance 1.5991). C23055 and C21488 followed at distances
--   1.6443 and 1.6459; C467 / bucket 637 was a later infrastructure-like
--   comparison candidate at distance 1.7006. Distance is a relative ranking
--   measure, not a probability or a confirmation of compromise.

--------------------------------------------------------------------------
-- Step 3a (diagnostic): expose the AUTH_CONNECTED profile that Step 3
-- uses as its C17693 reference. C19932 and C22409 are shown as negative
-- controls. This diagnostic intentionally includes confirmed buckets for
-- these known hosts, matching the reference-profile calculation in Step 3;
-- candidate hosts in Step 3 are still required to use clean buckets.
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
),
profile_buckets AS (
  SELECT
    staging_host,
    distinct_targets_in_bucket
  FROM
    bucketed
  WHERE
    distinct_targets_in_bucket >= 5
),
profiles AS (
  SELECT
    cb.staging_host,
    hb.distinct_targets_overall,
    COUNT(*)                           AS qualifying_bucket_count,
    MAX(cb.distinct_targets_in_bucket) AS max_targets_in_bucket,
    AVG(cb.distinct_targets_in_bucket) AS avg_targets_in_bucket
  FROM
    profile_buckets cb
    JOIN host_baseline hb
      ON hb.staging_host = cb.staging_host
  GROUP BY
    cb.staging_host,
    hb.distinct_targets_overall
)
SELECT *
FROM profiles
WHERE
  staging_host IN ('C17693', 'C19932', 'C22409')
ORDER BY
  distinct_targets_overall DESC;

-- FINAL OUTPUT CHECK:
--   The C17693 row must agree with Step 3's reference dimensions: 525 overall
--   targets, 42 qualifying >=5-target buckets, and a maximum bucket of 67.
--   C19932 and C22409 are retained as control rows so their broader
--   AUTH_CONNECTED burst shape can be compared with the reference. This is a
--   diagnostic profile view; it does not produce the new-host candidate list.

--------------------------------------------------------------------------
-- Step 4: Identify the identity behind the C17693-like candidate -- which
-- user_domain authenticated to the candidate staging host just before/during
-- the selected peak bucket? This is corroborating evidence for the strict
-- Step 3 result. Replace the bind values with the same row from Step 3:
--   :candidate_staging_host
--   :time_bucket
-- LogOff records are excluded because they describe session closure and add
-- substantial noise without identifying the actor that accessed the host.
-- LogOn/TGS/TGT/AuthMap records are retained, including failures.
--------------------------------------------------------------------------

SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (u IS user_domain) -[a IS auth_src_authenticated]-> (c IS computer)
    WHERE
      c.computer = :candidate_staging_host
      AND a.auth_orientation IN ('LogOn', 'TGS', 'TGT', 'AuthMap')
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

-- FINAL OUTPUT INTERPRETATION:
--   C5400 / bucket 326 is dominated by U3635@DOM1 with repeated successful
--   Kerberos and NTLM network logons plus TGS activity. ANONYMOUS LOGON@C625
--   is a secondary source clue; U1944@DOM1 and C5570$@DOM1 occur less often.
--   C3435 / bucket 206 is dominated by U66@DOM1, with dense Kerberos,
--   TGS/AuthMap, and some NTLM activity; C3435$@DOM1 is the host account and
--   may reflect machine or automated activity. C467 / bucket 637 is dominated
--   by its own machine account in the non-LogOff records and contains many
--   principals, making it a useful infrastructure comparison rather than a
--   clean identity signal. None of these identity results proves malicious
--   use. The supplied C3435/C467 extracts included LogOff rows; the current
--   final query excludes them, so rerun those bindings when a clean extract
--   is required.

--------------------------------------------------------------------------
-- Step 5: Multi-hop reach from the C17693-like candidate.
--
-- Separate direct AUTH_CONNECTED reach from computers reachable only through
-- a second AUTH_CONNECTED hop. The earlier combined 1-2 hop count cannot
-- distinguish direct reach from hub-mediated expansion and can be inflated
-- by repeated-vertex paths.
--
-- The result includes one SUMMARY row followed by one row per reached
-- computer. MIN_HOP identifies the shortest observed reach (1 or 2), while
-- REACH_CLASS distinguishes direct-only, direct-and-two-hop, and two-hop-only
-- computers. INTERMEDIATE_COMPUTERS identifies the possible second-hop hubs;
-- it is context, not an ordered path.
--
-- Simple-path guards exclude self-reach and repeated-vertex paths. The query
-- deliberately does not label any reachable computer as malicious.
--
-- FINAL REVIEW BINDINGS (run one candidate at a time):
--   primary candidate:          :candidate_staging_host = 'C5400'
--   secondary candidate:        :candidate_staging_host = 'C3435'
--   infrastructure comparison: :candidate_staging_host = 'C467'
--
-- ON OVERFLOW TRUNCATE WITH COUNT: the per-endpoint intermediate list is
-- capped at 4000 bytes. Counts remain exact if the display list is truncated.
--
-- FINAL OBSERVATIONS:
--   C5400: 69 direct, 601 two-hop-only, 28 direct/two-hop overlaps, and
--          670 total reachable computers (9.71x the direct reach).
--   C3435: 102 direct, 655 two-hop-only, 31 overlaps, and 757 total
--          reachable computers (7.42x the direct reach).
--   C467:   89 direct, 1,687 two-hop-only, 89 overlaps, and 1,776 total
--          reachable computers (19.96x the direct reach).
--   TOTAL_REACHABLE = DIRECT + TWO_HOP_ONLY; the overlap count is reported
--   separately and is not added again.
-- C467's much larger expansion and complete direct/two-hop overlap are
-- consistent with shared-hub infrastructure behavior; its reach volume
-- should not outweigh the Step 3/4 evidence for C5400 and C3435.
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
-- Step 6: Quantify reach -- rank the C17693-like candidate staging host and
-- every computer it can reach (Step 5's simple 1-2 hop walk) with PageRank on
-- the full cyber graph. A pivot that reaches structurally central computers
-- is a materially bigger risk than one that only reaches peripheral hosts.
--
-- The reach set uses the same repeated-vertex exclusions as Step 5 and
-- exposes MIN_HOP and REACH_CLASS, so direct targets can be distinguished
-- from computers reached only through a second hop. The candidate host is
-- included with MIN_HOP = 0.
--
-- The full cleaned reach set is pulled programmatically and PageRank is
-- computed once, joined against the staging host plus every reached computer.
-- Watch for the same hub-inflation risk Scenario 1 found with C586: on a
-- well-connected graph, a multi-hop walk can reach a high-PageRank hub
-- incidentally, not because this specific pivot is unusually dangerous.
-- Cross-check Step 3's host profile, Step 4's identity evidence, and Step
-- 5's reach class before treating a high score as significant on its own.
--
-- FINAL REVIEW BINDINGS (run one candidate at a time):
--   primary candidate:          :candidate_staging_host = 'C5400'
--   secondary candidate:        :candidate_staging_host = 'C3435'
--   infrastructure comparison: :candidate_staging_host = 'C467'
--
-- FINAL OBSERVATIONS:
-- C5400 and C3435 return the same highest-PageRank reached hubs, led by
-- C586, C612, C529, C625, C467, C457, C1065, and C528. Their repeated
-- appearance across candidates shows that PageRank is primarily reporting
-- shared graph centrality, not candidate-specific maliciousness.
-- C3435 itself has a low PageRank score (approximately 0.0000189), while
-- C5400 is not present in the displayed top-200 rows. C467 itself has a
-- much higher score (approximately 0.02739), reinforcing its role as a
-- central infrastructure comparison rather than a clean beachhead signal.
-- PageRank therefore provides impact context only; Step 3 profile similarity,
-- Step 4 identity evidence, and Step 5 direct reach remain the primary
-- evidence for prioritizing C5400 and C3435.
--------------------------------------------------------------------------

-- ALTER SESSION DISABLE PARALLEL QUERY;

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
-- Scope resolution: why C19932 and C22409 are out of this scenario
--
-- Six independent attempts to find a host-fan-out signal that would
-- catch C19932/C22409 the way Step 2 catches C17693, tested against the
-- same 3 known hosts plus, where noted, the full graph:
--   1. Hourly burst in ground-truth COMPROMISED data (the Step 1 control):
--      both max out at 2 distinct victims/hour, never close to 5. The
--      broader AUTH_CONNECTED Step 2 output is not the same measurement.
--   2. Daily volume (TRUNC(conn_time/86400) instead of /3600):
--      inconsistent even between the two hosts -- C22409's confirmed
--      days were cleanly its top 3 by volume, but C19932's confirmed and
--      unconfirmed days overlapped directly (an unconfirmed day at 13
--      sat above a confirmed day at 11).
--   3. Daily "new relationship" novelty (first time this staging host
--      ever reached this victim, via MIN(TRUNC(time/86400)) per pair):
--      promising in isolation -- 82% recall across the 2 hosts at a
--      >=5-new-targets/day threshold -- but at full graph scale, swamped
--      by noise up to 6,350/day (partly an observation-window boundary
--      effect on early days, partly genuinely huge hosts like C1798
--      that stay elevated the whole 58-day window).
--   4/5. Banding the novelty metric to [5,500] (calibrated from
--      C17693's confirmed max of 307), then adding a floor of >=20 on
--      overall fan-out (calibrated from C19932/C22409's confirmed
--      value of 24): each fix relocated the pollution rather than
--      removing it -- the floor itself became a new wall, with 189 of
--      200 candidate rows sitting at exactly the floor value.
--   6. Cross-referencing Scenario 1's own 69,648 validated persistence
--      candidates against their AUTH_CONNECTED onward reach: the overall
--      fan-out values for C17693/C19932/C22409 were 525/24/24 -- but C1798
--      alone scored 8,052, 15x C17693, despite never being confirmed as
--      anything.
--
-- Conclusion: host-to-host fan-out, at any granularity or combination
-- tried, does not separate C19932/C22409 from ordinary infrastructure.
-- That is not a tuning failure -- it is evidence these two are a
-- DIFFERENT shape than C17693. Both are already correctly identified by
-- 13-cyber_threat_scenario_credential_theft.sql (U66@DOM1 -> C17693,
-- U737@DOM1 -> C19932, U3486@DOM1 -> C22409 are all Scenario 1
-- persistence-band candidates): one identity persisting quietly on a
-- secondary computer, which also happens to touch a small number of
-- others -- not a cascading pivot campaign in its own right. This
-- scenario's validated scope is loud, high-volume, multi-victim
-- cascading pivots (C17693-shaped); quiet, few-victim secondary
-- compromises belong to Scenario 1's identity-persistence lens, not to
-- a host-fan-out search here.

-- Final v1 workflow conclusion:
--   Step 3 identified C5400 and C3435 as the strongest C17693-like
--   analyst-review candidates, with C467 retained as an infrastructure
--   comparison. Step 4 supplied corroborating identity context, while Step 5
--   showed broad two-hop expansion (C5400: 670 total; C3435: 757 total) and
--   Step 6 showed that the most prominent reached assets are shared global
--   graph hubs rather than candidate-specific proof. Prioritize C5400 for
--   profile similarity and clearer identity concentration, retain C3435 for
--   its larger direct/total reach, and do not treat either as a confirmed
--   beachhead without additional evidence.
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
